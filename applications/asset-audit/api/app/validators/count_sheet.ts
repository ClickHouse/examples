import vine from '@vinejs/vine'
export const draftValidator = vine.compile(vine.object({
  revision: vine.number().withoutDecimals().min(0).max(2147483646),
  counts: vine.array(vine.object({
    itemId: vine.number().withoutDecimals().min(1),
    counted: vine.number().withoutDecimals().min(0).max(1000000).nullable(),
  })).minLength(1).maxLength(100),
}))
export const finalizeValidator = vine.compile(vine.object({
  revision: vine.number().withoutDecimals().min(0).max(2147483646),
}))
