package com.alignpod.app

import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import androidx.core.content.ContextCompat
import com.google.android.play.core.integrity.IntegrityManagerFactory
import com.google.android.play.core.integrity.IntegrityTokenRequest
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.correctv1.bluetooth/unpair"
    private val INTEGRITY_CHANNEL = "com.alignpod.app/integrity"
    private var bondChannel: MethodChannel? = null
    private var bondStateReceiver: BroadcastReceiver? = null
    // Tracks per-device bond state so we can tell "was BONDING, now BOND_NONE"
    // (a real failure) apart from "was already BOND_NONE" (irrelevant).
    private val lastBondState = mutableMapOf<String, Int>()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Play Integrity channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, INTEGRITY_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "requestIntegrityToken") {
                    val nonce = call.argument<String>("nonce")
                    val cloudProjectNumber = call.argument<Int>("cloudProjectNumber")?.toLong()
                        ?: 204892022204L
                    if (nonce == null) {
                        result.error("INVALID_ARGUMENT", "nonce is null", null)
                        return@setMethodCallHandler
                    }
                    val manager = IntegrityManagerFactory.create(applicationContext)
                    val request = IntegrityTokenRequest.builder()
                        .setNonce(nonce)
                        .setCloudProjectNumber(cloudProjectNumber)
                        .build()
                    manager.requestIntegrityToken(request)
                        .addOnSuccessListener { response ->
                            result.success(response.token())
                        }
                        .addOnFailureListener { e ->
                            result.error("INTEGRITY_ERROR", e.message, null)
                        }
                } else {
                    result.notImplemented()
                }
            }

        // Bluetooth unpair channel
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler { call, result ->
            if (call.method == "removeBond") {
                val address = call.argument<String>("address")
                if (address != null) {
                    val success = removeBond(address)
                    result.success(success)
                } else {
                    result.error("INVALID_ARGUMENT", "Address is null", null)
                }
            } else if (call.method == "createBond") {
                val address = call.argument<String>("address")
                if (address != null) {
                    val success = createBond(address)
                    result.success(success)
                } else {
                    result.error("INVALID_ARGUMENT", "Address is null", null)
                }
            } else {
                result.notImplemented()
            }
        }
        bondChannel = channel
        registerBondStateReceiver()
    }

    /**
     * Listens for BOND_STATE_CHANGED so a real pairing failure (was BONDING,
     * now BOND_NONE — auth/SMP rejected) reaches Dart the instant it happens,
     * instead of Dart finding out only after a blind poll timeout.
     */
    private fun registerBondStateReceiver() {
        if (bondStateReceiver != null) return
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                if (intent.action != BluetoothDevice.ACTION_BOND_STATE_CHANGED) return
                val device = intent.getParcelableExtra<BluetoothDevice>(BluetoothDevice.EXTRA_DEVICE)
                    ?: return
                val newState = intent.getIntExtra(
                    BluetoothDevice.EXTRA_BOND_STATE,
                    BluetoothDevice.BOND_NONE
                )
                val address = device.address
                val previousState = lastBondState[address]
                lastBondState[address] = newState

                if (previousState == BluetoothDevice.BOND_BONDING &&
                    newState == BluetoothDevice.BOND_NONE
                ) {
                    val reason = intent.getIntExtra("android.bluetooth.device.extra.REASON", -1)
                    bondChannel?.invokeMethod(
                        "onBondFailed",
                        mapOf("address" to address, "reason" to reason)
                    )
                }
            }
        }
        // System-only broadcast (only the OS can send it) — NOT_EXPORTED is
        // correct and required on API 33+ targets.
        ContextCompat.registerReceiver(
            this,
            receiver,
            IntentFilter(BluetoothDevice.ACTION_BOND_STATE_CHANGED),
            ContextCompat.RECEIVER_NOT_EXPORTED
        )
        bondStateReceiver = receiver
    }

    override fun onDestroy() {
        bondStateReceiver?.let {
            try {
                unregisterReceiver(it)
            } catch (e: IllegalArgumentException) {
                // Already unregistered — safe to ignore.
            }
        }
        bondStateReceiver = null
        super.onDestroy()
    }

    @SuppressLint("MissingPermission")
    private fun createBond(address: String): Boolean {
        return try {
            val bluetoothAdapter = BluetoothAdapter.getDefaultAdapter()
            if (bluetoothAdapter == null) {
                false
            } else {
                val device = bluetoothAdapter.getRemoteDevice(address)
                when (device?.bondState) {
                    BluetoothDevice.BOND_BONDED -> true
                    BluetoothDevice.BOND_BONDING -> true
                    else -> {
                        // Bond explicitly over the LE transport. Plain
                        // createBond() means TRANSPORT_AUTO, which some OEM
                        // stacks (notably MIUI) resolve to the wrong transport
                        // for an address-only device — SMP then aborts within
                        // seconds (auth_status 0x8C) because the pod is LE-only.
                        try {
                            val method = device.javaClass.getMethod(
                                "createBond",
                                Int::class.javaPrimitiveType
                            )
                            method.invoke(device, BluetoothDevice.TRANSPORT_LE) as Boolean
                        } catch (e: Exception) {
                            device.createBond()
                        }
                    }
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
            false
        }
    }

    @SuppressLint("MissingPermission")
    private fun removeBond(address: String): Boolean {
        return try {
            val bluetoothAdapter = BluetoothAdapter.getDefaultAdapter()
            if (bluetoothAdapter == null) {
                false
            } else {
                val device = bluetoothAdapter.getRemoteDevice(address)
                if (device != null) {
                    // Use reflection to call removeBond() which is hidden in the API
                    val method = device.javaClass.getMethod("removeBond")
                    method.invoke(device) as Boolean
                } else {
                    false
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
            false
        }
    }
}
