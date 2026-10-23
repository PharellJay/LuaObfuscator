-- Regression: fractional literal obfuscation must stay value-exact and must
-- not throw on high-precision literals.
print(0.1234567890123)
print(3.14159265358979)
print(2.5)
print(100.0)
print(0.1)
print(1.0 / 3.0)
