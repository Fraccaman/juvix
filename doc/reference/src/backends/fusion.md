- Higher-level representation of the backend as a value/type in the language?
- It will be possible to typecheck as one project (set of source files which can co-reference each other) a multi-chain / multi-backend application.
- Architecturally, we would do this by having individual parameterisations of core per backend, one 'meta-parameterisation' combining them all, and a downcast function, run at compile time, that evaluates the term, walks all primitives, and either succeeds in translating them to a single backend or fails if terms from other backends are still present.