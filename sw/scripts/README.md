# Software Helper Scripts

## `gen_q16_coeff.py`

Generate signed Q16 sine/cosine coefficients for `image_geo_top`.

Examples:

```bash
python sw/scripts/gen_q16_coeff.py 45
python sw/scripts/gen_q16_coeff.py 90 --format c
```

Typical use:

- take the generated `sin_q16`
- write it to `ROT_SIN_Q16`
- take the generated `cos_q16`
- write it to `ROT_COS_Q16`
