import type { CurrencyDefinition } from './demo'

const canonicalMajorAmount = /^(0|[1-9][0-9]*)(?:\.([0-9]+))?$/
const canonicalIntegerAmount = /^-?(0|[1-9][0-9]*)$/

export type MoneyParseResult =
  | { ok: true; minorUnits: string }
  | { ok: false; reason: 'format' | 'precision' | 'zero' }

export function formatMinorUnits(
  minorUnits: string,
  currency: CurrencyDefinition,
  locale = 'en-US',
): string {
  if (!canonicalIntegerAmount.test(minorUnits)) {
    throw new Error('Money must be a canonical integer string.')
  }
  if (!Number.isInteger(currency.exponent) || currency.exponent < 0 || currency.exponent > 9) {
    throw new Error('Currency exponent is outside the supported range.')
  }

  const isNegative = minorUnits.startsWith('-')
  const unsignedAmount = BigInt(isNegative ? minorUnits.slice(1) : minorUnits)
  const scale = 10n ** BigInt(currency.exponent)
  const majorUnits = unsignedAmount / scale
  const fractionalUnits = unsignedAmount % scale
  const groupedMajorUnits = new Intl.NumberFormat(locale, {
    maximumFractionDigits: 0,
  }).format(majorUnits)

  if (currency.exponent === 0) {
    return `${currency.code} ${isNegative ? '−' : ''}${groupedMajorUnits}`
  }

  const decimalSeparator = new Intl.NumberFormat(locale, {
    minimumFractionDigits: 1,
    maximumFractionDigits: 1,
  })
    .formatToParts(0n)
    .find((part) => part.type === 'decimal')?.value

  if (!decimalSeparator) {
    throw new Error('The selected locale has no decimal separator.')
  }

  const exactFraction = fractionalUnits.toString().padStart(currency.exponent, '0')
  return `${currency.code} ${isNegative ? '−' : ''}${groupedMajorUnits}${decimalSeparator}${exactFraction}`
}

export function parseMajorUnits(input: string, exponent: number): MoneyParseResult {
  if (!Number.isInteger(exponent) || exponent < 0 || exponent > 9) {
    return { ok: false, reason: 'format' }
  }

  const match = canonicalMajorAmount.exec(input.trim())
  if (!match) return { ok: false, reason: 'format' }

  const wholePart = match[1]
  const fractionPart = match[2] ?? ''
  if (wholePart === undefined) return { ok: false, reason: 'format' }
  if (fractionPart.length > exponent) return { ok: false, reason: 'precision' }

  const scale = 10n ** BigInt(exponent)
  const paddedFraction = fractionPart.padEnd(exponent, '0')
  const minorUnits = BigInt(wholePart) * scale + BigInt(paddedFraction || '0')

  if (minorUnits === 0n) return { ok: false, reason: 'zero' }
  return { ok: true, minorUnits: minorUnits.toString() }
}
