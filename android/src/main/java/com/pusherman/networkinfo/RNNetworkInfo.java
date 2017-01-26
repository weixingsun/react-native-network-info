package com.pusherman.networkinfo;

import android.content.Context;
import android.net.wifi.WifiInfo;
import android.net.wifi.WifiManager;
import android.util.Log;
import android.net.DhcpInfo;

import com.facebook.react.bridge.Callback;
import com.facebook.react.bridge.NativeModule;
import com.facebook.react.bridge.ReactApplicationContext;
import com.facebook.react.bridge.ReactContext;
import com.facebook.react.bridge.ReactContextBaseJavaModule;
import com.facebook.react.bridge.ReactMethod;

import java.math.BigInteger;
import java.net.InetAddress;
import java.net.Inet4Address;
import java.net.UnknownHostException;
import java.net.SocketException;
import java.nio.ByteOrder;
import java.util.Map;
import java.util.Enumeration;
import java.net.NetworkInterface;
import java.lang.Runtime;
import java.lang.InterruptedException;
import java.io.IOException;

import net.mafro.android.wakeonlan.MagicPacket;

public class RNNetworkInfo extends ReactContextBaseJavaModule {
  WifiManager wifi;
  InetAddress inet;

  public static final String TAG = "RNNetworkInfo";

  public RNNetworkInfo(ReactApplicationContext reactContext) {
    super(reactContext);

    wifi = (WifiManager)reactContext.getSystemService(Context.WIFI_SERVICE);
  }

  @Override
  public String getName() {
    return TAG;
  }

  @ReactMethod
  public void getSSID(final Callback callback) {
    WifiInfo info = wifi.getConnectionInfo();
    
    // This value should be wrapped in double quotes, so we need to unwrap it.
    String ssid = info.getSSID();
    if (ssid.startsWith("\"") && ssid.endsWith("\"")) {
      ssid = ssid.substring(1, ssid.length() - 1);
    }
    
    callback.invoke(ssid);
  }

  @ReactMethod
  public void getIPAddress(final Callback callback) {
    WifiInfo info = wifi.getConnectionInfo();

    // The following is courtesy of Digital Rounin at
    //   http://stackoverflow.com/a/18638588 .

    // The endian-ness of `ip` is potentially varying, but we need it to be big-
    // endian.
    int ip = info.getIpAddress();

    // Convert little-endian to big-endian if needed.
    if (ByteOrder.nativeOrder().equals(ByteOrder.LITTLE_ENDIAN)) {
        ip = Integer.reverseBytes(ip);
    }

    // Now that the value is guaranteed to be big-endian, we can convert it to
    // an array whose first element is the high byte.
    byte[] ipByteArray = BigInteger.valueOf(ip).toByteArray();

    String ipAddressString;
    try {
        // `getByAddress()` wants network byte-order, aka big-endian. 
        // Good thing we planned ahead!
        ipAddressString = InetAddress.getByAddress(ipByteArray).getHostAddress();
    } catch (UnknownHostException ex) {
        Log.e(TAG, "Unable to determine IP address.");
        ipAddressString = null;
    }
    
    callback.invoke(ipAddressString);
      // String ipAddressString = null;

      // try {
      //     mainLoop:
      //     for (Enumeration<NetworkInterface> en = NetworkInterface.getNetworkInterfaces(); en.hasMoreElements();) {
      //         NetworkInterface intf = en.nextElement();

      //         for (Enumeration<InetAddress> enumIpAddr = intf.getInetAddresses(); enumIpAddr.hasMoreElements();) {
      //             InetAddress inetAddress = enumIpAddr.nextElement();

      //             if (!inetAddress.isLoopbackAddress() && inetAddress instanceof Inet4Address) {
      //                 ipAddressString = inetAddress.getHostAddress().toString();

      //                 break mainLoop;
      //             }
      //         }
      //     }
      // } catch (SocketException ex) {
      //     Log.e(TAG, ex.toString());
      // }

      // callback.invoke(ipAddressString);
  }

  @ReactMethod
  public void getRouterIPAddress(final Callback callback) {

    DhcpInfo dhcp = wifi.getDhcpInfo();
    int ip = dhcp.gateway;

    // Convert little-endian to big-endian if needed.
    if (ByteOrder.nativeOrder().equals(ByteOrder.LITTLE_ENDIAN)) {
        ip = Integer.reverseBytes(ip);
    }

    // Now that the value is guaranteed to be big-endian, we can convert it to
    // an array whose first element is the high byte.
    byte[] ipByteArray = BigInteger.valueOf(ip).toByteArray();

    String ipAddressString;
    try {
        // `getByAddress()` wants network byte-order, aka big-endian.
        // Good thing we planned ahead!
        ipAddressString = InetAddress.getByAddress(ipByteArray).getHostAddress();
    } catch (UnknownHostException ex) {
        Log.e(TAG, "Unable to determine IP address.");
        ipAddressString = null;
    }
    callback.invoke(ipAddressString);
  }

  @ReactMethod
  public void ping(final String url, final Callback callback) {
      boolean found = false;

      Runtime runtime = Runtime.getRuntime();
      try
      {
          Process  mIpAddrProcess = java.lang.Runtime.getRuntime().exec("/system/bin/ping -c1 -W1 " + url);
          int returnVal = mIpAddrProcess.waitFor();
          found = (returnVal==0);
      }
      catch (InterruptedException ignore)
      {
          ignore.printStackTrace();
          System.out.println(" Exception:"+ignore);
      } 
      catch (IOException e) 
      {
          e.printStackTrace();
          System.out.println(" Exception:"+e);
      }

      callback.invoke(found);
  }

  @ReactMethod
  public void wake(final String mac, final String ip, final Callback callback) {
    String formattedMac = null;

    try {
      formattedMac = MagicPacket.send(mac, ip);

    } catch(IllegalArgumentException iae) {
      Log.e(TAG, iae.getMessage());
    } catch(Exception e) {
      Log.e(TAG, e.getMessage());
    }

    callback.invoke(formattedMac);
  }

}
