package com.futureharmony.tb522fu.brightness.hook;

import de.robv.android.xposed.IXposedHookLoadPackage;
import de.robv.android.xposed.IXposedHookZygoteInit;
import de.robv.android.xposed.XposedBridge;
import de.robv.android.xposed.callbacks.XC_LoadPackage;

/**
 * LSPosed 模块主入口类
 */
public class MainHook implements IXposedHookLoadPackage, IXposedHookZygoteInit {

    private static final String TAG = "TB522FU_Brightness";

    @Override
    public void initZygote(StartupParam startupParam) throws Throwable {
        XposedBridge.log(TAG + ": Module initialized in Zygote");
    }

    @Override
    public void handleLoadPackage(XC_LoadPackage.LoadPackageParam lpparam) throws Throwable {
        if ("android".equals(lpparam.packageName)) {
            XposedBridge.log(TAG + ": Hooking system_server (android)");
            SystemServerHook.init(lpparam.classLoader);
        } else if ("com.android.systemui".equals(lpparam.packageName)) {
            XposedBridge.log(TAG + ": Hooking SystemUI");
            SystemUIHook.init(lpparam.classLoader);
        }
    }
}
