// Code generated by gobind. DO NOT EDIT.

// Java class irmagobridge.Signer is a proxy for talking to a Go program.
//
//   autogenerated by gobind -lang=java github.com/privacybydesign/irmamobile/irmagobridge
package irmagobridge;

import go.Seq;

public interface Signer {
	public byte[] publicKey(String keyname) throws Exception;
	public byte[] sign(String keyname, byte[] msg) throws Exception;
	
}

