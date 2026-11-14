package dev.nfctools.uid;

import android.os.Binder;
import android.os.IBinder;
import android.os.IInterface;
import android.os.Parcel;
import android.os.RemoteException;
import android.os.SystemClock;
import org.json.JSONObject;
import dev.nfctools.core.NciCodec;
import dev.nfctools.core.UidMutation;
import java.io.*;
import java.lang.reflect.*;
import java.nio.channels.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.Arrays;
import java.util.concurrent.*;
import java.security.MessageDigest;

/** Experimental, root-only Samsung long-pause Binder adapter. */
public final class UidCommand {
    private static final File STATE = new File("/data/adb/galaxy_watch_nfc_provide");
    private static final File DESIRED = new File(STATE, "desired-uid");
    private static final File BASELINE = new File(STATE, "factory.json");
    private static final String CONFIG = "/vendor/etc/libnfc-nxp.conf";
    private final Class<?> iface;
    private final Object adapter;
    private final Class<?> callbackType;
    private final File module;

    private UidCommand(File module) throws Exception {
        this.module = module;
        Class<?> manager = Class.forName("android.os.ServiceManager");
        IBinder binder = (IBinder) manager.getMethod("getService", String.class).invoke(null, "nfc");
        if (binder == null) throw new IOException("NFC service unavailable");
        iface = Class.forName("android.nfc.INfcAdapter");
        adapter = Class.forName("android.nfc.INfcAdapter$Stub").getMethod("asInterface", IBinder.class).invoke(null, binder);
        callbackType = Class.forName("android.nfc.INfcVendorNciCallback");
        iface.getMethod("pausePolling", long.class); // Fail closed on incompatible APIs.
        iface.getMethod("getMaxPausePollingTimeoutMs");
        iface.getMethod("resumePolling");
        iface.getMethod("sendVendorNciMessage", int.class, int.class, int.class, byte[].class);
        iface.getMethod("registerVendorExtensionCallback", callbackType);
        iface.getMethod("unregisterVendorExtensionCallback", callbackType);
    }
    private Object call(String name, Class<?>[] types, Object... args) throws Exception {
        try { return iface.getMethod(name, types).invoke(adapter, args); }
        catch (InvocationTargetException e) {
            Throwable cause = e.getCause();
            if (cause instanceof Exception) throw (Exception) cause;
            throw new IOException("Binder call failed", cause);
        }
    }
    private int state() throws Exception { return (Integer) call("getState", new Class<?>[0]); }
    private long maxPause() throws Exception { return (Long) call("getMaxPausePollingTimeoutMs", new Class<?>[0]); }
    private void activeModule() throws IOException {
        for (String name : new String[]{"disable", "remove", "update"})
            if (new File(module, name).exists()) throw new IOException("Module marked " + name + "; reboot/re-enable first");
    }
    private JSONObject probe() throws Exception {
        JSONObject j = ok("probe");
        j.put("adapterState", state()); j.put("maxPauseMs", maxPause());
        j.put("pauseSignature", "pausePolling(long)");
        j.put("nciWriteTested", false);
        j.put("warning", "Samsung has one global vendor callback slot; do not use UID operations during wallet/card activity");
        return j;
    }
    private final class Callback extends Binder implements InvocationHandler {
        private final int responseCode, notificationCode;
        private final Object proxy;
        private volatile int expected = -1;
        private volatile byte[] response;
        private volatile CountDownLatch pending;
        Callback() throws Exception {
            Class<?> stub = Class.forName("android.nfc.INfcVendorNciCallback$Stub");
            Field r = stub.getDeclaredField("TRANSACTION_onVendorResponseReceived"); r.setAccessible(true);
            Field n = stub.getDeclaredField("TRANSACTION_onVendorNotificationReceived"); n.setAccessible(true);
            responseCode = r.getInt(null); notificationCode = n.getInt(null);
            proxy = Proxy.newProxyInstance(callbackType.getClassLoader(), new Class<?>[]{callbackType}, this);
            attachInterface((IInterface) proxy, "android.nfc.INfcVendorNciCallback");
        }
        @Override public Object invoke(Object ignored, Method method, Object[] args) {
            switch (method.getName()) {
                case "asBinder": return this;
                case "toString": return "NfcToolsVendorCallback";
                case "hashCode": return System.identityHashCode(this);
                case "equals": return args != null && args[0] == proxy;
                case "onVendorResponseReceived": receive((Integer) args[0], (Integer) args[1], (byte[]) args[2]); return null;
                default: return null;
            }
        }
        private void receive(int gid, int oid, byte[] bytes) {
            CountDownLatch latch = pending;
            if (gid == 0 && oid == expected && bytes != null && latch != null && response == null) {
                response = bytes.clone(); latch.countDown();
            }
        }
        @Override protected boolean onTransact(int code, Parcel data, Parcel reply, int flags) throws RemoteException {
            if (code == INTERFACE_TRANSACTION) { if (reply != null) reply.writeString("android.nfc.INfcVendorNciCallback"); return true; }
            if (code == responseCode || code == notificationCode) {
                data.enforceInterface("android.nfc.INfcVendorNciCallback");
                int gid = data.readInt(), oid = data.readInt(); byte[] bytes = data.createByteArray();
                if (code == responseCode) receive(gid, oid, bytes);
                if (reply != null && (flags & IBinder.FLAG_ONEWAY) == 0) reply.writeNoException();
                return true;
            }
            return super.onTransact(code, data, reply, flags);
        }
        byte[] command(int oid, byte[] payload) throws Exception {
            expected = oid; response = null; pending = new CountDownLatch(1);
            int status = (Integer) call("sendVendorNciMessage", new Class<?>[]{int.class,int.class,int.class,byte[].class}, 1, 0, oid, payload);
            if (status != 0) throw new IOException("sendVendorNciMessage status=" + status + "; no successful command acknowledgement");
            if (!pending.await(1800, TimeUnit.MILLISECONDS)) throw new IOException("NCI response timeout; result unknown");
            byte[] result = response;
            expected = -1; pending = null;
            return result;
        }
    }
    private interface Work<T> { T run(Callback c) throws Exception; }
    private <T> T transaction(Work<T> work) throws Exception {
        activeModule();
        if (state() != 3) throw new IOException("Turn NFC on first");
        // Per command scope, the OS auto-resumes even if this process crashes.
        long timeout = Math.min(6000, maxPause());
        if (timeout < 5000) throw new IOException("Finite pause budget below 5000 ms; refusing transaction");
        Callback c = new Callback();
        boolean pausedByUs = false, registered = false;
        Exception cleanup = null;
        try {
            int result = (Integer) call("pausePolling", new Class<?>[]{long.class}, timeout);
            if (result != 1 && result != 2) throw new IOException("Unexpected pause result=" + result);
            pausedByUs = result == 1; // Already stopped (2): never resume another caller's state.
            // Samsung exposes a single callback slot. This API is explicitly experimental.
            call("registerVendorExtensionCallback", new Class<?>[]{callbackType}, c.proxy); registered = true;
            return work.run(c);
        } finally {
            if (registered) try { call("unregisterVendorExtensionCallback", new Class<?>[]{callbackType}, c.proxy); }
                catch (Exception e) { cleanup = e; }
            if (pausedByUs) try {
                int result = (Integer) call("resumePolling", new Class<?>[0]);
                if (result != 1 && result != 2) throw new IOException("resumePolling status=" + result);
            } catch (Exception e) { cleanup = e; }
            if (cleanup != null) throw new IOException("Cleanup failed; NFC may need toggling", cleanup);
        }
    }
    private byte[] get() throws Exception {
        return transaction(c -> NciCodec.parseGet(c.command(3, new byte[]{1,0x33})));
    }
    private void writeAndVerify(byte[] value) throws Exception {
        byte[] observed = NciCodec.decode(new JSONObject(read(BASELINE)).getString("observedDefault"));
        UidMutation.writeAndVerify(controller(), value, observed);
    }
    private UidMutation.Controller controller() {
        return new UidMutation.Controller() {
            public byte[] get() throws Exception { return UidCommand.this.get(); }
            public void set(byte[] value) throws Exception {
                // A separate finite OS pause for each command/read-back/rollback.
                transaction(c -> { NciCodec.checkSet(c.command(2, NciCodec.setPayload(value))); return null; });
            }
        };
    }
    private JSONObject set(byte[] value, boolean persistent) throws Exception {
        activeModule();
        byte[] original = factory(); // Validate the device-derived baseline before any write.
        JSONObject baseline = new JSONObject(read(BASELINE));
        UidMutation.apply(controller(), value, original, NciCodec.decode(baseline.getString("observedDefault")), () -> {
            if (persistent) atomic(DESIRED, NciCodec.hex(value) + "\n");
            else Files.deleteIfExists(DESIRED.toPath()); // Temporary mode cancels old desired state.
        });
        JSONObject j = ok(persistent ? "persist" : "set");
        j.put("uid", NciCodec.hex(value)); j.put("controllerReadBackVerified", true);
        j.put("persistent", persistent); j.put("airUidVerified", false);
        return j;
    }
    private byte[] factory() throws Exception {
        if (!BASELINE.isFile()) throw new IOException("Factory baseline missing: install the UID tools module first");
        JSONObject j = new JSONObject(read(BASELINE));
        String fingerprint = android.os.Build.FINGERPRINT;
        if (!fingerprint.equals(j.getString("fingerprint"))) throw new IOException("Firmware changed; recapture factory baseline before writes");
        String config = read(new File(CONFIG));
        byte[] current = NciCodec.factoryValue(config);
        if (!j.getString("configSha256").equals(NciCodec.hex(MessageDigest.getInstance("SHA-256").digest(config.getBytes(StandardCharsets.UTF_8)))))
            throw new IOException("Vendor configuration hash changed; recapture baseline after review");
        byte[] saved = NciCodec.decode(j.getString("uid")); NciCodec.checkLength(saved);
        if (!Arrays.equals(saved, current)) throw new IOException("Vendor baseline changed; refusing reset/write");
        return saved;
    }
    private JSONObject captureFactory() throws Exception {
        String config = read(new File(CONFIG));
        byte[] baseline = NciCodec.factoryValue(config);
        JSONObject j = new JSONObject();
        j.put("fingerprint", android.os.Build.FINGERPRINT); j.put("config", CONFIG);
        j.put("uid", NciCodec.hex(baseline)); j.put("length", baseline.length);
        j.put("configSha256", NciCodec.hex(MessageDigest.getInstance("SHA-256").digest(config.getBytes(StandardCharsets.UTF_8))));
        if (BASELINE.isFile()) {
            JSONObject existing = new JSONObject(read(BASELINE));
            if (j.getString("fingerprint").equals(existing.getString("fingerprint")) && j.getString("configSha256").equals(existing.getString("configSha256")))
                return ok("capture-default").put("baselineReused", true);
            if (DESIRED.exists()) throw new IOException("Baseline changed with persistence enabled; unpersist and review first");
        }
        j.put("observedDefault", NciCodec.hex(get()));
        j.put("observedDefaultEvidence", "Controller parameter before this module's first write; not an air UID measurement");
        atomic(BASELINE, j.toString() + "\n");
        return ok("capture-default").put("factory", j);
    }
    private JSONObject reset() throws Exception {
        byte[] value = factory();
        // Cancellation is durable even when NFC is currently off or a reset fails.
        Files.deleteIfExists(DESIRED.toPath());
        try { writeAndVerify(value); }
        catch (Exception e) { throw new IOException("Persistence disabled, but controller reset NOT verified; toggle NFC to reload vendor default", e); }
        return ok("reset").put("factoryLength", value.length).put("controllerReadBackVerified", true).put("persistent", false);
    }
    private JSONObject status() throws Exception {
        JSONObject j = ok("status").put("persistent", DESIRED.isFile());
        if (DESIRED.isFile()) j.put("desiredUid", NciCodec.hex(NciCodec.uid(read(DESIRED).trim())));
        j.put("factoryBaselinePresent", BASELINE.isFile());
        File health = new File(STATE, "watch-status.json");
        if (health.isFile()) j.put("lastWatchStatus", new JSONObject(read(health)));
        return j;
    }
    private void watch() throws Exception {
        try (RandomAccessFile f = new RandomAccessFile(new File(STATE, "watch.lock"), "rw");
             FileLock lock = f.getChannel().tryLock()) {
            if (lock == null) return;
            int previousState = -1, attempts = 0;
            String previousDesired = "";
            while (true) {
                try { activeModule(); } catch (IOException e) { return; }
                String target = DESIRED.isFile() ? read(DESIRED).trim() : "";
                int now;
                try { now = state(); } catch (Exception e) { now = -1; }
                if (!target.equals(previousDesired) || (now == 3 && previousState != 3)) attempts = 0;
                if (!target.isEmpty() && now == 3 && attempts < 3) {
                    attempts++;
                    try (RandomAccessFile op = new RandomAccessFile(new File(STATE, "operation.lock"), "rw");
                         FileLock l = op.getChannel().tryLock()) {
                        if (l != null && DESIRED.isFile() && target.equals(read(DESIRED).trim())) {
                            factory();
                            byte[] value = NciCodec.uid(target), actual = get();
                            if (!Arrays.equals(value, actual)) {
                                try { writeAndVerify(value); }
                                catch (Exception e) {
                                    JSONObject base = new JSONObject(read(BASELINE));
                                    byte[] restore = Arrays.equals(actual, NciCodec.decode(base.getString("observedDefault"))) ? factory() : actual;
                                    try { writeAndVerify(restore); } catch (Exception rollback) { e.addSuppressed(rollback); }
                                    throw e;
                                }
                            }
                            attempts = 3;
                            atomic(new File(STATE, "watch-status.json"), ok("watch").put("verified", true).put("elapsedRealtimeMs", SystemClock.elapsedRealtime()).toString());
                        } else attempts--;
                    } catch (Exception e) {
                        atomic(new File(STATE, "watch-status.json"), new JSONObject().put("ok", false).put("attempt", attempts).put("error", describe(e)).toString());
                    }
                }
                previousState = now; previousDesired = target;
                Thread.sleep(10000); // No repeated NCI requests once verified / retry budget exhausted.
            }
        }
    }
    private static String read(File f) throws IOException {
        if (f.length() > 128*1024) throw new IOException("Oversized input file");
        return new String(Files.readAllBytes(f.toPath()), StandardCharsets.UTF_8);
    }
    private static void atomic(File target, String text) throws IOException {
        File tmp = File.createTempFile(".state-", ".tmp", STATE);
        try {
            try (FileOutputStream out = new FileOutputStream(tmp)) { out.write(text.getBytes(StandardCharsets.UTF_8)); out.getFD().sync(); }
            Files.move(tmp.toPath(), target.toPath(), StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING);
        } finally { Files.deleteIfExists(tmp.toPath()); }
    }
    private static JSONObject ok(String operation) throws Exception { return new JSONObject().put("ok", true).put("operation", operation); }
    private static String describe(Throwable t) {
        StringBuilder s = new StringBuilder();
        for (int i = 0; t != null && i < 5; i++, t = t.getCause()) {
            if (i > 0) s.append(" <- "); s.append(t.getClass().getSimpleName()).append(": ").append(t.getMessage());
        }
        return s.toString();
    }
    public static void main(String[] args) {
        int exit = 0;
        try {
            if (android.os.Process.myUid() != 0) throw new SecurityException("Root required");
            if (args.length < 2) throw new IllegalArgumentException("Usage: <module-dir> probe|get|set UID|persist UID|reset|unpersist|status|capture-default|watch");
            File module = new File(args[0]).getCanonicalFile();
            String command = args[1];
            if (!module.isDirectory()) throw new IOException("Module directory unavailable");
            // Validate all arguments before touching NFC or state.
            byte[] target = null;
            if (command.equals("set") || command.equals("persist")) {
                if (args.length != 3) throw new IllegalArgumentException("UID argument required"); target = NciCodec.uid(args[2]);
            } else if (args.length != 2) throw new IllegalArgumentException("Unexpected arguments");
            if (!command.matches("probe|get|set|persist|reset|unpersist|status|capture-default|watch")) throw new IllegalArgumentException("Unknown command");
            UidCommand tool = new UidCommand(module);
            if (command.equals("watch")) { tool.watch(); System.exit(0); return; }
            try (RandomAccessFile f = new RandomAccessFile(new File(STATE, "operation.lock"), "rw");
                 FileLock lock = f.getChannel().tryLock()) {
                if (lock == null) throw new IOException("BUSY: another UID operation is active");
                JSONObject result;
                switch (command) {
                    case "probe": result = tool.probe(); break;
                    case "get": byte[] value = tool.get(); result = ok("get").put("length", value.length).put("uid", NciCodec.hex(value)).put("airUidVerified", false); break;
                    case "set": result = tool.set(target, false); break;
                    case "persist": result = tool.set(target, true); break;
                    case "reset": result = tool.reset(); break;
                    case "unpersist": Files.deleteIfExists(DESIRED.toPath()); result = ok(command).put("persistent", false).put("controllerChanged", false); break;
                    case "status": result = tool.status(); break;
                    case "capture-default": result = tool.captureFactory(); break;
                    default: throw new IllegalArgumentException("Unknown command");
                }
                System.out.println(result.toString());
            }
        } catch (Exception e) {
            exit = 1;
            try { System.out.println(new JSONObject().put("ok", false).put("error", describe(e)).toString()); }
            catch (Exception ignored) { System.err.println(describe(e)); }
        }
        System.exit(exit); // Binder threads must not keep the root command alive.
    }
}
