---
max_pure_loc: 300
---

# loc-guardian Extraction Rules

## TypeScript / React

- **Types/interfaces** → `types.ts` in same directory
- **Constants & config objects** → `constants.ts`
- **Pure utility functions** → `utils.ts` or `<name>Utils.ts`
- **Sub-components** → new `<ComponentName>.tsx` file
- **Custom hooks** → `use<Name>.ts` in same directory
- **Store actions/selectors** → keep in store file; split by feature if >300 LOC

## Rust

- **Tauri commands** → `commands.rs` within the feature module
- **Data types/structs** → `types.rs` within the feature module
- **Helper/utility functions** → `utils.rs` within the feature module
- **Tests** → keep in `#[cfg(test)]` block at bottom of each file
