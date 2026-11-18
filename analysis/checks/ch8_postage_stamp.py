"""ch8_postage_stamp.py, Chapter 8 sec. 8.1: the postage-stamp trio and its ratios.
Run from the repo root:  python3 analysis/checks/ch8_postage_stamp.py
Constants are transcribed from the two commission staff transmission charge matrices:
  puct2025docket57491matrix, Attachment A p. 2 (TOTAL TCOS, Total ERCOT Postage Stamp Rate, 2024 Average 4CP)
  puct2013docket40946matrix, TOTAL row, whose own footnote says the sum of the approved TCOS
  "will not match the postage stamp rate multiplied by 2012 ERCOT Average 4CP because the TCOS for
  most TSPs was approved under the ERCOT 4CP from prior years."
"""
M = {2013: dict(tcos=2_001_794_430, rate=30.950950, cp4_kw=66_014_375.9),
     2025: dict(tcos=5_446_864_795, rate=68.547301, cp4_kw=81_042_657)}
for y, m in M.items():
    implied = m["tcos"] / m["cp4_kw"]
    print(f"{y}: stamp ${m['rate']:.2f}/kW-yr on {m['cp4_kw']/1e6:.1f} GW, TCOS ${m['tcos']/1e9:.2f} bn; "
          f"TCOS / 4CP = ${implied:.2f} (stamp {100*(m['rate']/implied-1):.1f}% above); "
          f"stamp x 4CP = ${m['rate']*m['cp4_kw']/1e9:.3f} bn")
a, b = M[2013], M[2025]
print(f"2013 -> 2025: rate +{100*(b['rate']/a['rate']-1):.0f}%, cost +{100*(b['tcos']/a['tcos']-1):.0f}%, "
      f"peak +{100*(b['cp4_kw']/a['cp4_kw']-1):.0f}%")
