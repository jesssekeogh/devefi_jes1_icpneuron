import { Ed25519KeyIdentity } from '@dfinity/identity';

const base64ToUInt8Array = (base64String: string): Uint8Array => {
  return Buffer.from(base64String, 'base64');
};

const minterPublicKey = 'Uu8wv55BKmk9ZErr6OIt5XR1kpEGXcOSOC1OYzrAwuk=';
const minterPrivateKey =
  'N3HB8Hh2PrWqhWH2Qqgr1vbU9T3gb1zgdBD8ZOdlQnVS7zC/nkEqaT1kSuvo4i3ldHWSkQZdw5I4LU5jOsDC6Q==';

const pubArr = Uint8Array.from(Buffer.from(minterPublicKey, 'base64'));
const privArr = Uint8Array.from(Buffer.from(minterPrivateKey, 'base64'));

export const minterIdentity = Ed25519KeyIdentity.fromKeyPair(
  pubArr.buffer,   // exactly 32 bytes
  privArr.buffer,  // exactly 64 bytes
);