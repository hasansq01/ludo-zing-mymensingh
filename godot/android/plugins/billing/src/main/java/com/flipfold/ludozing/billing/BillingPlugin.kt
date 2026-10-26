package com.flipfold.ludozing.billing

import android.app.Activity
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.android.billingclient.api.BillingClient
import com.android.billingclient.api.BillingClientStateListener
import com.android.billingclient.api.BillingFlowParams
import com.android.billingclient.api.BillingResult
import com.android.billingclient.api.ConsumeParams
import com.android.billingclient.api.PendingPurchasesParams
import com.android.billingclient.api.ProductDetails
import com.android.billingclient.api.Purchase
import com.android.billingclient.api.PurchasesUpdatedListener
import com.android.billingclient.api.QueryProductDetailsParams
import com.android.billingclient.api.QueryPurchasesParams
import org.godotengine.godot.Dictionary
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.SignalInfo
import org.godotengine.godot.plugin.UsedByGodot

/**
 * Google Play Billing for Ludo Zing's gem packs (Godot v2 Android plugin, Engine singleton "BillingPlugin"; the
 * name is not "Billing" so it never shadows the GDScript class_name Billing). Consumable in-app products only
 * (INAPP). The GDScript side is res://scripts/net/billing.gd (class Billing); the method and signal names below are
 * snake_case on purpose: GDScript calls them by these names. Contract: server/ECONOMY_V1.md sections 2 and 6.
 *
 * The plugin never acknowledges or consumes a purchase by itself: the server verifies the token with the Play
 * Developer API and consumes it (which also acknowledges). consume() is only a fallback the game can call.
 *
 * Every method is safe to call at any time and never throws into GDScript; answers come as signals, always on the
 * UI thread. A purchase dictionary is {product_id, token, order_id, state ("purchased" | "pending"), account_id}.
 */
class BillingPlugin(godot: Godot) : GodotPlugin(godot) {

    companion object {
        private const val TAG = "LudoZingBilling"
        /** Our own code for "no connection to Google Play" (BillingResponseCode values are >= -3). */
        private const val NOT_CONNECTED = -100
        private const val UNKNOWN_PRODUCT = -101
        private const val MAX_BACKOFF_MS = 60_000L

        private val STRING = String::class.java
        private val INT = Int::class.javaObjectType
        private val DICT = Dictionary::class.java
        private val ARRAY = Array<Any>::class.java

        val SIG_CONNECTED = SignalInfo("connected")
        val SIG_DISCONNECTED = SignalInfo("disconnected")
        // (code, message) the setup failed; a retryable failure is retried with backoff
        val SIG_CONNECT_FAILED = SignalInfo("connect_failed", INT, STRING)
        // (list of {id, title, description, price, price_micros, currency})
        val SIG_PRODUCTS = SignalInfo("products", ARRAY)
        val SIG_QUERY_FAILED = SignalInfo("query_failed", INT, STRING)
        // ({product_id, token, order_id, state, account_id}) paid
        val SIG_PURCHASED = SignalInfo("purchased", DICT)
        // (product_id) paid with a slow method (cash, carrier billing): not final yet
        val SIG_PENDING = SignalInfo("pending", STRING)
        val SIG_PURCHASE_FAILED = SignalInfo("purchase_failed", INT, STRING)
        val SIG_CANCELED = SignalInfo("canceled")
        // (list of purchase dictionaries) unconsumed purchases
        val SIG_OWNED = SignalInfo("owned", ARRAY)
        val SIG_CONSUMED = SignalInfo("consumed", STRING)
        // (token, code, message)
        val SIG_CONSUME_FAILED = SignalInfo("consume_failed", STRING, INT, STRING)
    }

    private val main = Handler(Looper.getMainLooper())
    private var client: BillingClient? = null
    private var wantConnection = false
    private var connecting = false
    private var backoffMs = 1_000L
    private val details = HashMap<String, ProductDetails>()

    override fun getPluginName() = "BillingPlugin"

    override fun getPluginSignals(): Set<SignalInfo> = setOf(
        SIG_CONNECTED, SIG_DISCONNECTED, SIG_CONNECT_FAILED, SIG_PRODUCTS, SIG_QUERY_FAILED, SIG_PURCHASED,
        SIG_PENDING, SIG_PURCHASE_FAILED, SIG_CANCELED, SIG_OWNED, SIG_CONSUMED, SIG_CONSUME_FAILED,
    )

    override fun onMainDestroy() {
        wantConnection = false
        main.removeCallbacksAndMessages(null)
        try { client?.endConnection() } catch (_: Throwable) {}
        client = null
        super.onMainDestroy()
    }

    // ---------- connection ----------

    /** Connects to Google Play. -> connected | connect_failed(code, message); disconnected later if the service drops. */
    @UsedByGodot
    fun start_connection() {
        runOnUiThread {
            wantConnection = true
            if (client?.isReady == true) {
                emitSignal(SIG_CONNECTED.name)
                return@runOnUiThread
            }
            connect()
        }
    }

    private fun connect() {
        if (connecting || !wantConnection) return
        try {
            val c = client ?: BillingClient.newBuilder((activity ?: context).applicationContext)
                .setListener(purchasesListener)
                .enablePendingPurchases(PendingPurchasesParams.newBuilder().enableOneTimeProducts().build())
                .build()
                .also { client = it }
            connecting = true
            c.startConnection(object : BillingClientStateListener {
                override fun onBillingSetupFinished(result: BillingResult) {
                    runOnUiThread {
                        connecting = false
                        if (result.responseCode == BillingClient.BillingResponseCode.OK) {
                            backoffMs = 1_000L
                            emitSignal(SIG_CONNECTED.name)
                        } else {
                            emitSignal(SIG_CONNECT_FAILED.name, result.responseCode, result.debugMessage)
                            if (retryable(result.responseCode)) scheduleReconnect()
                        }
                    }
                }

                override fun onBillingServiceDisconnected() {
                    runOnUiThread {
                        connecting = false
                        emitSignal(SIG_DISCONNECTED.name)
                        scheduleReconnect()
                    }
                }
            })
        } catch (t: Throwable) {
            connecting = false
            Log.w(TAG, "connect failed", t)
            emitSignal(SIG_CONNECT_FAILED.name, BillingClient.BillingResponseCode.ERROR, t.message ?: t.javaClass.simpleName)
            scheduleReconnect()
        }
    }

    private fun retryable(code: Int) = code == BillingClient.BillingResponseCode.SERVICE_UNAVAILABLE ||
        code == BillingClient.BillingResponseCode.SERVICE_DISCONNECTED ||
        code == BillingClient.BillingResponseCode.ERROR ||
        code == BillingClient.BillingResponseCode.NETWORK_ERROR

    private fun scheduleReconnect() {
        if (!wantConnection) return
        val delay = backoffMs
        backoffMs = minOf(backoffMs * 2, MAX_BACKOFF_MS)
        main.postDelayed({ if (client?.isReady != true) connect() }, delay)
    }

    /** The ready client, or null (the caller then answers NOT_CONNECTED and kicks a reconnect). */
    private fun ready(): BillingClient? {
        val c = client
        if (c != null && c.isReady) return c
        if (wantConnection && !connecting) connect()
        return null
    }

    // ---------- products ----------

    /** Prices and titles of the given in-app product ids. -> products(list) | query_failed(code, message). */
    @UsedByGodot
    fun query_products(ids: Array<String>) {
        runOnUiThread {
            val c = ready()
            if (c == null) {
                emitSignal(SIG_QUERY_FAILED.name, NOT_CONNECTED, "not connected to Google Play")
                return@runOnUiThread
            }
            try {
                val list = ids.filter { it.isNotBlank() }.distinct().map {
                    QueryProductDetailsParams.Product.newBuilder().setProductId(it)
                        .setProductType(BillingClient.ProductType.INAPP).build()
                }
                if (list.isEmpty()) {
                    emitSignal(SIG_PRODUCTS.name, arrayOf<Any>())
                    return@runOnUiThread
                }
                val params = QueryProductDetailsParams.newBuilder().setProductList(list).build()
                c.queryProductDetailsAsync(params) { result, productResult ->
                    runOnUiThread {
                        if (result.responseCode != BillingClient.BillingResponseCode.OK) {
                            emitSignal(SIG_QUERY_FAILED.name, result.responseCode, result.debugMessage)
                            return@runOnUiThread
                        }
                        val out = ArrayList<Any>()
                        for (pd in productResult.productDetailsList.orEmpty()) {
                            details[pd.productId] = pd
                            val offer = pd.oneTimePurchaseOfferDetails ?: continue
                            val d = Dictionary()
                            d["id"] = pd.productId
                            d["title"] = pd.title
                            d["description"] = pd.description
                            d["price"] = offer.formattedPrice
                            d["price_micros"] = offer.priceAmountMicros
                            d["currency"] = offer.priceCurrencyCode
                            out.add(d)
                        }
                        emitSignal(SIG_PRODUCTS.name, out.toTypedArray())
                    }
                }
            } catch (t: Throwable) {
                Log.w(TAG, "query_products failed", t)
                emitSignal(SIG_QUERY_FAILED.name, BillingClient.BillingResponseCode.ERROR, t.message ?: t.javaClass.simpleName)
            }
        }
    }

    // ---------- purchase ----------

    /**
     * Opens Google Play's purchase sheet for a product returned by query_products (call that first). The account id
     * is attached as the obfuscated account id (Play keeps it with the purchase; the server can check it).
     * The result arrives as purchased | pending | canceled | purchase_failed.
     */
    @UsedByGodot
    fun purchase(product_id: String, obfuscated_account_id: String) {
        runOnUiThread {
            val c = ready()
            val act: Activity? = activity
            if (c == null || act == null) {
                emitSignal(SIG_PURCHASE_FAILED.name, NOT_CONNECTED, "not connected to Google Play")
                return@runOnUiThread
            }
            val pd = details[product_id]
            if (pd == null) {
                emitSignal(SIG_PURCHASE_FAILED.name, UNKNOWN_PRODUCT, "unknown product: call query_products first")
                return@runOnUiThread
            }
            try {
                val product = BillingFlowParams.ProductDetailsParams.newBuilder().setProductDetails(pd).build()
                val flow = BillingFlowParams.newBuilder().setProductDetailsParamsList(listOf(product))
                if (obfuscated_account_id.isNotEmpty()) flow.setObfuscatedAccountId(obfuscated_account_id)
                val result = c.launchBillingFlow(act, flow.build())
                if (result.responseCode != BillingClient.BillingResponseCode.OK) {
                    emitSignal(SIG_PURCHASE_FAILED.name, result.responseCode, result.debugMessage)
                }
            } catch (t: Throwable) {
                Log.w(TAG, "purchase failed", t)
                emitSignal(SIG_PURCHASE_FAILED.name, BillingClient.BillingResponseCode.ERROR, t.message ?: t.javaClass.simpleName)
            }
        }
    }

    private val purchasesListener = PurchasesUpdatedListener { result, purchases ->
        runOnUiThread {
            when (result.responseCode) {
                BillingClient.BillingResponseCode.OK -> {
                    if (purchases.isNullOrEmpty()) {
                        emitSignal(SIG_PURCHASE_FAILED.name, BillingClient.BillingResponseCode.ERROR, "no purchase returned")
                    } else {
                        for (p in purchases) {
                            when (p.purchaseState) {
                                Purchase.PurchaseState.PURCHASED -> emitSignal(SIG_PURCHASED.name, purchaseDict(p))
                                Purchase.PurchaseState.PENDING -> emitSignal(SIG_PENDING.name, p.products.firstOrNull() ?: "")
                                else -> {}
                            }
                        }
                    }
                }
                BillingClient.BillingResponseCode.USER_CANCELED -> emitSignal(SIG_CANCELED.name)
                else -> emitSignal(SIG_PURCHASE_FAILED.name, result.responseCode, result.debugMessage)
            }
        }
    }

    private fun purchaseDict(p: Purchase): Dictionary {
        val d = Dictionary()
        d["product_id"] = p.products.firstOrNull() ?: ""
        d["token"] = p.purchaseToken
        d["order_id"] = p.orderId ?: ""
        d["state"] = if (p.purchaseState == Purchase.PurchaseState.PENDING) "pending" else "purchased"
        d["account_id"] = p.accountIdentifiers?.obfuscatedAccountId ?: ""
        return d
    }

    // ---------- owned / consume ----------

    /** Purchases that were paid but not consumed yet (after a crash, or a server that was down). -> owned(list). */
    @UsedByGodot
    fun query_purchases() {
        runOnUiThread {
            val c = ready()
            if (c == null) {
                emitSignal(SIG_QUERY_FAILED.name, NOT_CONNECTED, "not connected to Google Play")
                return@runOnUiThread
            }
            try {
                val params = QueryPurchasesParams.newBuilder().setProductType(BillingClient.ProductType.INAPP).build()
                c.queryPurchasesAsync(params) { result, list ->
                    runOnUiThread {
                        if (result.responseCode != BillingClient.BillingResponseCode.OK) {
                            emitSignal(SIG_QUERY_FAILED.name, result.responseCode, result.debugMessage)
                            return@runOnUiThread
                        }
                        val out = list.filter { it.purchaseState == Purchase.PurchaseState.PURCHASED }
                            .map { purchaseDict(it) as Any }
                        emitSignal(SIG_OWNED.name, out.toTypedArray())
                    }
                }
            } catch (t: Throwable) {
                Log.w(TAG, "query_purchases failed", t)
                emitSignal(SIG_QUERY_FAILED.name, BillingClient.BillingResponseCode.ERROR, t.message ?: t.javaClass.simpleName)
            }
        }
    }

    /** Fallback: consumes (and so acknowledges) a purchase. The server normally does it. -> consumed | consume_failed. */
    @UsedByGodot
    fun consume(token: String) {
        runOnUiThread {
            val c = ready()
            if (c == null) {
                emitSignal(SIG_CONSUME_FAILED.name, token, NOT_CONNECTED, "not connected to Google Play")
                return@runOnUiThread
            }
            try {
                val params = ConsumeParams.newBuilder().setPurchaseToken(token).build()
                c.consumeAsync(params) { result, t ->
                    runOnUiThread {
                        if (result.responseCode == BillingClient.BillingResponseCode.OK) {
                            emitSignal(SIG_CONSUMED.name, t)
                        } else {
                            emitSignal(SIG_CONSUME_FAILED.name, t, result.responseCode, result.debugMessage)
                        }
                    }
                }
            } catch (t: Throwable) {
                Log.w(TAG, "consume failed", t)
                emitSignal(SIG_CONSUME_FAILED.name, token, BillingClient.BillingResponseCode.ERROR, t.message ?: t.javaClass.simpleName)
            }
        }
    }
}
