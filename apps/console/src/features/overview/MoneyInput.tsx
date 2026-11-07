import { useId, useState } from 'react'
import type { CurrencyDefinition } from './demo'
import { parseMajorUnits } from './money'

type MoneyInputProps = {
  currency: CurrencyDefinition
  onMinorUnitsChange: (minorUnits: string | null) => void
}

export function MoneyInput({ currency, onMinorUnitsChange }: MoneyInputProps) {
  const inputId = useId()
  const hintId = useId()
  const errorId = useId()
  const [value, setValue] = useState('')
  const parsed = value === '' ? null : parseMajorUnits(value, currency.exponent)

  const errorMessage =
    parsed?.ok === false
      ? parsed.reason === 'precision'
        ? `Use no more than ${currency.exponent} decimal places for ${currency.code}.`
        : parsed.reason === 'zero'
          ? 'Enter an amount greater than zero.'
          : 'Enter digits with an optional decimal point.'
      : undefined

  function handleChange(nextValue: string) {
    setValue(nextValue)
    const nextResult = nextValue === '' ? null : parseMajorUnits(nextValue, currency.exponent)
    onMinorUnitsChange(nextResult?.ok ? nextResult.minorUnits : null)
  }

  return (
    <div className="money-input">
      <label htmlFor={inputId}>Amount in {currency.code}</label>
      <input
        id={inputId}
        type="text"
        inputMode="decimal"
        autoComplete="off"
        spellCheck={false}
        value={value}
        aria-invalid={errorMessage ? true : undefined}
        aria-describedby={errorMessage ? `${hintId} ${errorId}` : hintId}
        onChange={(event) => handleChange(event.currentTarget.value)}
      />
      <p id={hintId} className="money-input__hint">
        Enter a positive amount with up to {currency.exponent} decimal places.
      </p>
      {errorMessage && (
        <p id={errorId} className="money-input__error" role="alert">
          {errorMessage}
        </p>
      )}
    </div>
  )
}
