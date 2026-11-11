/**
 * `heic-decode` ne livre pas de types (2.1.0). On ne déclare que ce qu'on
 * appelle : un décodage, un bitmap RGBA — voir `services/photoFormat.ts`.
 */
declare module "heic-decode" {
  interface DecodedImage {
    width: number;
    height: number;
    /** RGBA, quatre octets par pixel. */
    data: Uint8Array;
  }

  export default function decode(options: { buffer: Uint8Array }): Promise<DecodedImage>;
}
