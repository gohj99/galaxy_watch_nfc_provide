package dev.nfctools.tests;

import dev.nfctools.core.*;
import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.io.IOException;

public final class CoreTest {
    private static int checks;
    private interface Action { void run() throws Exception; }
    private static void equal(byte[] a, String hex) { checks++; if (!NciCodec.hex(a).equals(hex)) throw new AssertionError(NciCodec.hex(a)+" != "+hex); }
    private static void fails(Action a) throws Exception { checks++; try { a.run(); } catch (Exception expected) { return; } throw new AssertionError("Expected failure"); }
    private static final byte[] DEFAULT = NciCodec.decode("08000000"), A = NciCodec.uid("AABBCCDD"), B = NciCodec.uid("11223344");
    private static class Fake implements UidMutation.Controller {
        byte[] current = DEFAULT.clone();
        List<String> writes = new ArrayList<>();
        boolean corruptOnce, denyRollback;
        public byte[] get() { return current.clone(); }
        public void set(byte[] v) throws Exception {
            writes.add(NciCodec.hex(v));
            if (denyRollback && writes.size()>1) throw new IOException("rollback rejected");
            if (corruptOnce) { current=B.clone(); corruptOnce=false; }
            else current=v.length==0 ? DEFAULT.clone() : v.clone();
        }
    }
    public static void main(String[] args) throws Exception {
        equal(NciCodec.uid("aabbccdd"), "AABBCCDD");
        for (String bad : new String[]{"", "1234", "AABBCCDD00", "AABBCCGG", "AA BB CC DD", "AABBCCDD;id"}) fails(() -> NciCodec.uid(bad));
        equal(NciCodec.setPayload(A), "013304AABBCCDD"); equal(NciCodec.setPayload(new byte[0]), "013300");
        equal(NciCodec.parseGet(NciCodec.decode("00013300")), "");
        equal(NciCodec.parseGet(NciCodec.decode("0001330408000000")), "08000000");
        for (String bad : new String[]{"", "00013304", "01013300", "00023300", "0001330100", "00013200", "0001330000"}) fails(() -> NciCodec.parseGet(NciCodec.decode(bad)));
        NciCodec.checkSet(NciCodec.decode("0000")); checks++;
        fails(() -> NciCodec.checkSet(NciCodec.decode("0100"))); fails(() -> NciCodec.checkSet(NciCodec.decode("00")));
        String fixture = new String(Files.readAllBytes(Paths.get(args[0])), StandardCharsets.UTF_8);
        equal(NciCodec.factoryValue(fixture), "");
        fails(() -> NciCodec.factoryValue(fixture.replace("20, 02, 33, 11", "20, 02, 34, 11")));
        fails(() -> NciCodec.factoryValue(fixture+"\n"+fixture));
        fails(() -> NciCodec.factoryValue(fixture.replace("33, 00", "33, 04")));
        fails(() -> NciCodec.factoryValue(fixture.replace("28, 01, 00", "33, 01, 00")));
        Fake good = new Fake(); boolean[] saved = {false};
        UidMutation.apply(good, A, new byte[0], DEFAULT, () -> { saved[0]=true; });
        checks++; if (!saved[0]) throw new AssertionError("Commit missing"); equal(good.current,"AABBCCDD");
        Fake mismatch = new Fake(); mismatch.corruptOnce=true;
        fails(() -> UidMutation.apply(mismatch,A,new byte[0],DEFAULT,() -> { throw new AssertionError("Do not commit mismatched read-back"); }));
        equal(mismatch.current,"08000000"); checks++; if (!mismatch.writes.equals(Arrays.asList("AABBCCDD", ""))) throw new AssertionError("Default rollback must send zero-length");
        Fake commitFailure = new Fake();
        fails(() -> UidMutation.apply(commitFailure,A,new byte[0],DEFAULT,() -> { throw new IOException("disk full"); }));
        equal(commitFailure.current,"08000000");
        Fake fixedBefore = new Fake(); fixedBefore.current=B.clone();
        fails(() -> UidMutation.apply(fixedBefore,A,new byte[0],DEFAULT,() -> { throw new IOException("disk full"); })); equal(fixedBefore.current,"11223344");
        Fake brokenRollback = new Fake(); brokenRollback.corruptOnce=true; brokenRollback.denyRollback=true;
        checks++; try { UidMutation.apply(brokenRollback,A,new byte[0],DEFAULT,() -> {}); throw new AssertionError(); }
        catch (IOException e) { if (!e.getMessage().contains("rollback unverified")) throw e; }
        UidMutation.writeAndVerify(good,new byte[0],DEFAULT); equal(good.current,"08000000");
        Type4Tag t = new Type4Tag(NciCodec.decode("D1010554027A686869"));
        equal(t.process(NciCodec.decode("00B0000002")),"6985");
        equal(t.process(NciCodec.decode("00A4040007D276000085010100")),"9000");
        equal(t.process(NciCodec.decode("00A4000C02E103")),"9000");
        equal(t.process(NciCodec.decode("00B000000F")),"000F2000FF00FF0406E104040000FF9000");
        equal(t.process(NciCodec.decode("00A4000C02E104")),"9000");
        equal(t.process(NciCodec.decode("00B0000002")),"00099000");
        equal(t.process(NciCodec.decode("00B0000209")),"D1010554027A6868699000");
        equal(t.process(NciCodec.decode("00D600000100")),"6D00");
        equal(t.process(NciCodec.decode("00B0FFFF01")),"6A86");
        equal(t.process(NciCodec.decode("00B0002001")),"6B00");
        equal(t.process(NciCodec.decode("80B0000002")),"6E00");
        equal(t.process(new byte[0]),"6700");
        equal(t.process(NciCodec.decode("00A4040007D2760000850101FFFF")),"6700");
        equal(t.process(NciCodec.decode("00A4040007D2760000850102")),"6A82");
        equal(t.process(NciCodec.decode("00B0000002")),"6985");
        fails(() -> new Type4Tag(new byte[1023]));
        // Deterministic malformed-APDU coverage: no parser crashes or oversized responses.
        Random random = new Random(7);
        for (int i=0;i<5000;i++) {
            byte[] input = new byte[random.nextInt(300)]; random.nextBytes(input);
            byte[] response = t.process(input); checks++;
            if (response.length<2 || response.length>258) throw new AssertionError("Bad APDU response length");
        }
        System.out.println("PASS "+checks+" core checks (includes 5000 malformed APDUs); physical NFC not tested");
    }
}
