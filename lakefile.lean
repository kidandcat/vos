import Lake
open Lake DSL

package vos where
  leanOptions := #[
    ⟨`autoImplicit, false⟩,
    ⟨`relaxedAutoImplicit, false⟩,
    ⟨`maxHeartbeats, 800000⟩
  ]

@[default_target]
lean_lib Vos

lean_lib Tests where
  globs := #[.one `Tests.Ref]

@[test_driver]
lean_exe «vos-tests» where
  root := `Tests.Main

lean_exe «vos-demo» where
  root := `Vos.Host.Demo
