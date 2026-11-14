package dev.nfctools.core;

import java.util.Arrays;

/** Small read-only NFC Forum Type 4 NDEF application, no wallet/card keys. */
public final class Type4Tag {
    public static final int MAX_NDEF = 1022;
    private static final byte[] AID = NciCodec.decode("D2760000850101");
    private static final byte[] CC = NciCodec.decode("000F2000FF00FF0406E104040000FF");
    private final byte[] file;
    private boolean appSelected;
    private int selectedFile;
    public Type4Tag(byte[] ndef) {
        if (ndef == null || ndef.length > MAX_NDEF) throw new IllegalArgumentException("NDEF exceeds 1022 bytes");
        file = new byte[ndef.length+2];
        file[0] = (byte)(ndef.length >> 8); file[1] = (byte)ndef.length;
        System.arraycopy(ndef, 0, file, 2, ndef.length);
    }
    private static byte[] sw(int code) { return new byte[]{(byte)(code>>8), (byte)code}; }
    public synchronized byte[] process(byte[] apdu) {
        if (apdu == null || apdu.length < 4) return sw(0x6700);
        if (apdu[0] != 0) return sw(0x6E00);
        int ins = apdu[1]&255, p1 = apdu[2]&255, p2 = apdu[3]&255;
        if (ins == 0xA4) {
            if (apdu.length < 5) return sw(0x6700);
            int lc = apdu[4]&255;
            if (apdu.length != lc+5 && apdu.length != lc+6) return sw(0x6700);
            byte[] data = Arrays.copyOfRange(apdu, 5, 5+lc);
            if (p1 == 4 && p2 == 0) {
                appSelected = Arrays.equals(data, AID); selectedFile = 0;
                return sw(appSelected ? 0x9000 : 0x6A82);
            }
            if (!appSelected) return sw(0x6985);
            if (p1 != 0 || (p2 != 0 && p2 != 0x0C) || lc != 2) return sw(0x6A86);
            int id = ((data[0]&255)<<8) | (data[1]&255);
            if (id != 0xE103 && id != 0xE104) { selectedFile = 0; return sw(0x6A82); }
            selectedFile = id;
            return sw(0x9000);
        }
        if (ins == 0xB0) {
            if (apdu.length != 5) return sw(0x6700);
            if (!appSelected || selectedFile == 0) return sw(0x6985);
            if ((p1 & 0x80) != 0) return sw(0x6A86); // SFI/extended offsets unsupported.
            int offset = (p1<<8)|p2, le = apdu[4]&255;
            if (le == 0) le = 256;
            byte[] data = selectedFile == 0xE103 ? CC : file;
            if (offset >= data.length) return sw(0x6B00);
            int n = Math.min(le, data.length-offset);
            byte[] out = Arrays.copyOfRange(data, offset, offset+n+2);
            out[n] = (byte)0x90; out[n+1] = 0;
            return out;
        }
        // UPDATE BINARY and proprietary card commands are deliberately not implemented.
        return sw(0x6D00);
    }
}
