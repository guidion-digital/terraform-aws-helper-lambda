# Lessons Learned

Correction memory for whoever (or whatever) regenerates `AI/CONTEXT.md`. Short, imperative entries only. Prune an entry once the generator stops making the mistake.

## Repo-specific facts the code reads as the opposite of

- `master` is not the integration branch. `acc` is the default branch and the PR target; CI merges `acc` into `master` and tags from there. Do not describe `master` as the main branch.
- `specification.vpc_enabled` gates security-group creation only, not VPC attachment. Do not describe it as "enables VPC support".
- `var.application_name` is required by callers and referenced nowhere in the module. Do not invent a use for it, and do not recommend deleting it — it is a breaking interface change.
- `var.name` names the zip artefact, not any AWS resource. Do not describe it as the Lambda's name; `specification.function_name` is that.
- `data.aws_region.current` and `data.aws_caller_identity.current` are declared and unused. Do not infer account- or region-awareness from their presence.
- `lambda_arn_for_permission` exists but no known caller reads it. Do not list it as consumed.
- `outputs.tf` `httpMethod` emits `POST` when the caller sets nothing and `null` when the caller sets `http_method`. Read the ternary before describing it; the naming suggests the reverse.
- `http_method` is declared in the callers' endpoint schema and set by none of them. Before calling the `outputs.tf` `httpMethod` ternary a live bug, check whether any caller sets the field; today none does, so the emitted value is always `POST`, which is correct for `aws_proxy`. The extension's `httpMethod` is the integration's method, not the route's.

## Generation traps hit on the first pass

- An object never equals `{}` in Terraform. When reasoning about `var.specification.vpc_config == {}`, test it — do not assume the guard works because it reads like it should, and do not assume it is broken in production either. What is established: the guard never fires, so the block always renders, and the provider accepts it. What is not established: what AWS does with an all-empty block at apply. Do not upgrade the second into a claim.
- Do not use the example's applied `terraform.tfstate` as proof of current behaviour. It is untracked, was written by an older Terraform, and can disagree with the code at HEAD. Test against the code instead.
- Terraform silently discards object attributes absent from a type constraint rather than erroring. The example's method-level `headers` block is dead config. Do not document it as a supported field, and do not report it as a hard error.
- Do not read the caller workflow's job conditions in isolation. `workflow-change`'s two-part condition (`local-stack-apply-result != 'success'` and `terraform-file-changes-result == 'false'`) is not two independent tests: in `terrappy`'s `tfc-test-helper-module-apply.yaml`, the apply job is skipped when no `.tf` file changed, so the second condition _causes_ the first. It is a correct docs-only guard, not a hole that merges failed applies. Read the reusable workflow before characterising the gating.
- Do not describe the review or release gate from the workflow files alone. Read those settings before writing that anything ships "without review" — but do not enumerate them in `AI/CONTEXT.md`. **This repo is public**, and the branch-protection API returns 401 unauthenticated, so the settings (especially who may bypass review) are non-public access-control detail. Point at the branch settings instead of reproducing them.
- Keep threat framing proportionate. Every known defect in this module fails closed: a broken apply, a denied invocation, or dropped config. Do not present them as an attacker-usable weakness, and do not treat the wide default _egress_ rule as a widening — Terraform strips a security group's default allow-all egress, so the module's default restores AWS's own conventional behaviour. Ingress defaults to empty.
- `*.zip` and `terraform.tfstate*` at the repo root and under `examples/` are untracked and `.gitignore`-covered build residue from local example runs. Check `git ls-files` before reporting them as committed state or as a leak.

## Scope and framing

- This is a Terraform Registry module (`guidion-digital/helper-lambda/aws`) whose consumer pins `~> 1.0`. Frame findings as published-interface concerns, not internal cleanups.
- Statements about the consumer come from a local checkout of terraform-aws-app-apigw-lambda, not from its `HEAD`. Say so rather than asserting them as current.
- Never raise `review_confidence` because the draft was thorough. Only human validation raises it.
