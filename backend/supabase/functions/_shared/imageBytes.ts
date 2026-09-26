// What a stored "image" actually is, judged by its bytes, never by what the
// client says. Pure, so vitest imports it directly.

/** JPEG files start with the SOI marker FF D8 followed by another marker (FF). */
export function isJpeg(bytes: Uint8Array): boolean {
  return bytes.length >= 3 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff
}
