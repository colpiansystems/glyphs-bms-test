# Glyphs BMS v2 Modular Build

This package was created from the latest uploaded Glyphs BMS file: `index (2)(3).html`.

## Folder structure

```text
index.html
css/styles.css
js/app.js
sql/01_schema.sql
sql/02_rls_policies.sql
sql/03_migration.sql
sql/04_pin_auth.sql
backup/index_original_monolithic.html
```

## How to host on GitHub Pages

1. Open your GitHub repository.
2. Upload the whole folder contents, not only `index.html`.
3. The repository root should contain `index.html`, plus the `css`, `js`, `sql`, and `backup` folders.
4. Commit the changes.
5. Open your GitHub Pages link and hard refresh the browser.

## Important

- GitHub Pages will automatically load `index.html`.
- `index.html` now loads design from `css/styles.css`.
- `index.html` now loads application logic from `js/app.js`.
- The original single-file version is preserved in `backup/index_original_monolithic.html`.
- SQL files are included only for Supabase setup/reference. They are not loaded by GitHub Pages.

## Next version recommendation

This is the first safe modular step. The app is now split into HTML, CSS, and JavaScript.
The next deeper refactor can split `js/app.js` into smaller modules like `payments.js`, `jobs.js`, `dashboard.js`, `auth.js`, and `production.js`.
