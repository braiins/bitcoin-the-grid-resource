# Bitcoin: The Grid Resource

The LaTeX sources of *Bitcoin: The Grid Resource. Why the Power Grid Pays Bitcoin
Miners to Be Flexible* by Vit Ficl (Braiins Publishing, 2026, ISBN
978-80-909695-4-4), and the code and data behind every number it computes.

The book itself is published by Braiins Publishing: see
https://braiins.com/books. The printed edition was set from the tree tagged
`v1.0` (see the book's copyright page); check out that tag to reproduce it.

## Layout

- `book/`: the LaTeX sources (`main.tex`, `chapters/`), the bibliography
  (`references.bib`) and the figures (`images/`).
- `analysis/checks/`: the scripts that compute the book's numbers. Each printed
  number carries a `% src:` comment at the end of its source line naming the script
  and console line it comes from.
- `analysis/figures/`: one script per figure.
- `analysis/data/`: the committed data (ERCOT prices and demand, hashprice, fleet
  curves) and the fetchers that rebuild it from public sources; see
  `analysis/data/README.md`.
- `analysis/ch5-backtest/`: Chapter 5's control-loop backtest kit; see its README.
- The historical calculator of Chapter 9 (`analysis/calculator/`) is not in this
  tree yet and follows in a later update. Its data is already here:
  `analysis/checks/ch9_calculator_export.R` builds
  `analysis/data/ch9_calculator_data.json` on the same engine as the Chapter 9
  ledger, then stops where it would write that data into the missing page.

The methodology appendix of the book lists which script produces each chapter's
numbers.

## Build the book

```
cd book && latexmk -pdf -interaction=nonstopmode main.tex
```

Needs a TeX distribution with latexmk and biber.

## Rerun the numbers

Run the scripts from the repository root, for example
`Rscript analysis/checks/ch9_optimal_stack.R` or
`python3 analysis/checks/check_src_comments.py`. R scripts use data.table, ggplot2,
ggrepel and patchwork; Python scripts use the standard library unless their header
says otherwise.

## License

- The book's text and figures (`book/`): Copyright © 2026 Braiins Systems, s.r.o.,
  licensed under the Creative Commons Attribution-ShareAlike 4.0 International
  License (CC BY-SA 4.0), see `LICENSES/CC-BY-SA-4.0.txt`. Material quoted or
  reproduced from other sources, and the cover design, are not covered by this
  license and remain under their owners' terms.
- The code (the scripts and kits under `analysis/`): MIT License,
  see `LICENSES/MIT.txt`.
- The data files under `analysis/data/` keep the terms of their sources.
  `analysis/data/README.md` gives each file's origin and license posture, and the
  fetcher that rebuilds it.
