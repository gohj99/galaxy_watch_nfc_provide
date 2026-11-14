package dev.nfctools.core;

import java.util.Arrays;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/** Only the standard NFCID1 parameter is allowed; no arbitrary NCI command API. */
public final class NciCodec {
    private NciCodec() {}
    public static String hex(byte[] value) {
        StringBuilder s = new StringBuilder();
        for (byte b : value) s.append(String.format(java.util.Locale.ROOT, "%02X", b & 255));
        return s.toString();
    }
    public static byte[] uid(String text) {
        if (text == null || !text.matches("[0-9a-fA-F]{8}"))
            throw new IllegalArgumentException("UID must contain exactly 8 hexadecimal characters (4 bytes)");
        return decode(text);
    }
    public static byte[] decode(String text) {
        if (text == null || !text.matches("(?:[0-9a-fA-F]{2})*"))
            throw new IllegalArgumentException("Invalid hexadecimal encoding");
        byte[] out = new byte[text.length() / 2];
        for (int i = 0; i < out.length; i++) out[i] = (byte) Integer.parseInt(text.substring(i*2, i*2+2), 16);
        return out;
    }
    public static void checkLength(byte[] value) {
        if (value.length != 0 && value.length != 4)
            throw new IllegalArgumentException("Only default (length 0) or fixed 4-byte NFCID1 is implemented");
    }
    public static byte[] setPayload(byte[] value) {
        checkLength(value);
        byte[] out = new byte[3 + value.length];
        out[0] = 1; out[1] = 0x33; out[2] = (byte) value.length;
        System.arraycopy(value, 0, out, 3, value.length);
        return out;
    }
    public static byte[] parseGet(byte[] response) {
        if (response == null || response.length < 4 || response[0] != 0 || response[1] != 1 || response[2] != 0x33)
            throw new IllegalArgumentException("Unexpected CORE_GET_CONFIG response");
        int length = response[3] & 255;
        if (response.length != 4 + length) throw new IllegalArgumentException("Truncated/trailing GET response");
        byte[] value = Arrays.copyOfRange(response, 4, response.length);
        checkLength(value);
        return value;
    }
    public static void checkSet(byte[] response) {
        // Samsung firmware variants return either a one-byte status or the
        // complete two-byte NCI response. Both successful forms start with 0.
        if (response == null || response.length < 1 || response[0] != 0)
            throw new IllegalArgumentException("CORE_SET_CONFIG was not acknowledged successfully");
    }
    public static byte[] factoryValue(String conf) {
        String clean = conf.replaceAll("(?m)#.*$", "");
        Matcher m = Pattern.compile("(?m)^\\s*NXP_CORE_CONF\\s*=\\s*\\{([^}]*)\\}").matcher(clean);
        if (!m.find()) throw new IllegalArgumentException("NXP_CORE_CONF not found");
        String body = m.group(1).trim();
        if (m.find()) throw new IllegalArgumentException("Duplicate NXP_CORE_CONF");
        if (!body.matches("(?s)[0-9a-fA-F]{2}(?:\\s*,\\s*[0-9a-fA-F]{2})*\\s*,?"))
            throw new IllegalArgumentException("Unsupported NXP_CORE_CONF format");
        byte[] command = decode(body.replaceAll("[\\s,]", ""));
        if (command.length < 4 || command[0] != 0x20 || command[1] != 2 || (command[2]&255) != command.length-3)
            throw new IllegalArgumentException("Invalid CORE_SET_CONFIG header/length");
        int pos = 4, count = command[3] & 255;
        byte[] found = null;
        for (int i = 0; i < count; i++) {
            if (pos+2 > command.length) throw new IllegalArgumentException("Truncated TLV");
            int id = command[pos++] & 255;
            // This block must use standard one-byte parameter IDs. Vendor TLVs live elsewhere.
            if (id >= 0xA0) throw new IllegalArgumentException("Vendor TLV in standard CORE block");
            int len = command[pos++] & 255;
            if (pos+len > command.length) throw new IllegalArgumentException("Truncated TLV value");
            if (id == 0x33) {
                if (found != null) throw new IllegalArgumentException("Duplicate NFCID1 parameter");
                found = Arrays.copyOfRange(command, pos, pos+len);
            }
            pos += len;
        }
        if (pos != command.length || found == null) throw new IllegalArgumentException("Invalid TLV count or missing NFCID1");
        checkLength(found);
        return found;
    }
}
