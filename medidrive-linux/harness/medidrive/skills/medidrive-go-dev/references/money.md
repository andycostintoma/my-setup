# Money & Currency

## The Only Rule: `*big.Rat` — Always

ALL currency amounts use `*big.Rat` from `math/big`. **Never** `float32` or `float64`.

### Declaring money fields

```go
type Order struct {
    totalAmount    *big.Rat  // ✅ *big.Rat + "Amount" suffix
    taxAmount      *big.Rat
    discountAmount *big.Rat
}
```

### Creating money values

```go
// From integer cents
amount := big.NewRat(9999, 100)  // $99.99

// From string
amount, _ := new(big.Rat).SetString("99.99")

// Zero
zero := big.NewRat(0, 1)
```

### Arithmetic

```go
// Addition
sum := new(big.Rat).Add(priceAmount, taxAmount)

// Multiplication
itemTotal := new(big.Rat).Mul(
    priceAmount,
    big.NewRat(int64(quantity), 1),
)

// Accumulation
total := big.NewRat(0, 1)
for _, item := range items {
    itemTotal := new(big.Rat).Mul(item.PriceAmount(), big.NewRat(int64(item.Qty()), 1))
    total.Add(total, itemTotal)
}
```

### In tests

```go
// ✅ Always *big.Rat
expected := big.NewRat(9999, 100)
assert.Equal(t, expected, order.TotalAmount())

// ❌ NEVER floats
assert.Equal(t, 99.99, order.Total())  // WRONG
```

### Naming

ALL money variable/field/parameter names MUST end with `Amount`:

```go
totalAmount, taxAmount, discountAmount, priceAmount  // ✅
total, tax, discount, price                          // ❌
```
