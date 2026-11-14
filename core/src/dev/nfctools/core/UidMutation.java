package dev.nfctools.core;

import java.util.Arrays;
import java.io.IOException;

/** Transport-independent mutation, verification and rollback, exercised with a fake controller. */
public final class UidMutation {
    private UidMutation() {}
    public interface Controller { byte[] get() throws Exception; void set(byte[] value) throws Exception; }
    public interface Commit { void save() throws Exception; }
    public static void writeAndVerify(Controller io, byte[] value, byte[] observedDefault) throws Exception {
        io.set(value);
        byte[] expected = value.length == 0 ? observedDefault : value;
        if (!Arrays.equals(expected, io.get())) throw new IOException("Controller read-back mismatch");
    }
    public static void apply(Controller io, byte[] value, byte[] factory, byte[] observedDefault, Commit commit) throws Exception {
        NciCodec.checkLength(value); NciCodec.checkLength(factory); NciCodec.checkLength(observedDefault);
        byte[] before = io.get();
        byte[] rollback = Arrays.equals(before, observedDefault) ? factory : before;
        try {
            writeAndVerify(io, value, observedDefault);
            commit.save();
        } catch (Exception e) {
            try { writeAndVerify(io, rollback, observedDefault); }
            catch (Exception failure) {
                e.addSuppressed(failure);
                throw new IOException("UID operation failed AND rollback unverified; toggle NFC before further use", e);
            }
            throw new IOException("UID operation failed; previous controller parameter restored; persistent state not committed", e);
        }
    }
}
