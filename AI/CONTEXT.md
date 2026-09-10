---
repo: terraform-aws-helper-lambda
project_name: Helper Lambda (Terrappy framework)
owner: Cinfra
domain: infrastructure
criticality: high
summary: Terraform helper module that creates a single AWS Lambda function (optionally versioned, aliased, and VPC-attached) and returns the OpenAPI `paths` fragment that an API Gateway REST API needs in order to integrate with it. Published to the public Terraform Registry as `guidion-digital/helper-lambda/aws` and consumed by the API Lambda App module.
main_stack:
  - Terraform (HCL)
  - AWS Lambda
  - Python (example payloads only)
  - GitHub Actions
main_systems:
  - AWS Lambda
  - AWS API Gateway (REST, OpenAPI-driven)
  - AWS VPC / security groups
  - Terraform Registry
  - HCP Terraform (Terraform Cloud)
  - LocalStack
last_reviewed: 2026-09-09
review_confidence: low
generated_by: AI-assisted
validated_by: none
---

# Helper Lambda (Terrappy framework)

## Overview

This is a leaf-level Terraform module in the [Terrappy](https://github.com/guidion-digital/terrappy) framework. It creates one `aws_lambda_function` from a source directory, optionally publishes a version and points a configurable alias at it, optionally creates a security group and attaches the function to a VPC, and — its distinguishing job — renders the caller's endpoint definitions into an OpenAPI `paths` object carrying the `x-amazon-apigateway-integration` extensions that API Gateway needs.

It is not consumed directly by product teams. Its intended caller is [terraform-aws-app-apigw-lambda](https://github.com/guidion-digital/terraform-aws-app-apigw-lambda), which instantiates it once per Lambda with `for_each` and deep-merges the resulting `paths_spec` fragments into a single API Gateway REST API body. Because it is published to the public Terraform Registry and the caller pins `~> 1.0`, every 1.x release reaches consumers automatically.

- **Owner:** Cinfra (`@guidion-digital/cinfra` per `.github/CODEOWNERS`)
- **Main stack:** Terraform/HCL, AWS Lambda, GitHub Actions; Python only in `examples/test_app/dist` as test payloads
- **Environment:** No environment of its own. It is a module — resources land in whatever AWS account and region the caller's provider points at. CI exercises it against LocalStack via the Terrappy test workflows.

---

## Purpose and responsibilities

Does:

- Package a source directory into a zip via the `archive` provider and create one `aws_lambda_function` from it
- Publish a Lambda version and maintain a configurable alias (`latest_version_alias`, default `live`) pointing at the latest published version, when `publish_version` is true
- Create one security group and its ingress/egress rules when `vpc_enabled` is true, and merge that security group with any caller-supplied `security_group_ids`
- Render the caller's `endpoints` map into an OpenAPI `paths` object (`paths_spec`), including `x-amazon-apigateway-integration`, request-validator extensions, and a CORS-filling special case for `mock` integrations
- Echo the whole input `specification` back out, so the caller can reuse values it has already resolved without recomputing them

Does not do (delegated to):

- Create the API Gateway REST API, stages, deployments, or API keys → terraform-aws-app-apigw-lambda
- Create `aws_lambda_permission` for API Gateway invocation → terraform-aws-app-apigw-lambda (deliberately: `source_arn` depends on the REST API, which depends on the Lambda ARN being present in the OpenAPI body, so granting it here would be a dependency cycle)
- Create the IAM execution role → the caller passes `role_arn`
- Create the VPC or subnets → the caller passes `vpc_config`; this module only creates the security group
- Create SQS queues, DynamoDB tables, or event-source mappings → terraform-aws-helper-supporting-resources and terraform-aws-app-apigw-lambda
- Deep-merge multiple Lambdas' `paths_spec` fragments into one API body → terraform-aws-app-apigw-lambda
- Deploy the Lambda source code as a release artefact; the zip is built from `source_dir` at plan time on every run

---

## Source of truth / data ownership

This module owns no business domain objects. What it owns are infrastructure resources and one interface fragment, and getting that boundary right matters because several of the values it produces are consumed by a sibling module that also derives them independently.

| Domain object / data            | Source of truth                     | This system role | Notes                                                                                                          |
| ------------------------------- | ----------------------------------- | ---------------- | -------------------------------------------------------------------------------------------------------------- |
| Lambda function resource        | This module                         | Owns             | One `aws_lambda_function` per instantiation; `function_name` is supplied by the caller, not constructed here   |
| Lambda version / alias          | This module                         | Owns             | `aws_lambda_alias.live` named from `latest_version_alias`; only created when `publish_version` is true         |
| Lambda deployment package (zip) | This module                         | Owns             | Built by `data.archive_file.this` from `specification.source_dir`, written to `${path.module}/${var.name}.zip` |
| Lambda security group           | This module                         | Owns             | Only when `vpc_enabled` is true; egress/ingress rules from `security_group_rules`                              |
| OpenAPI `paths` fragment        | This module                         | Owns             | Emitted as the `paths_spec` output; assembled into a whole API body by the caller                              |
| IAM execution role              | Caller                              | Reads            | Passed in as `specification.role_arn`                                                                          |
| VPC, subnets                    | Caller (or the caller's VPC module) | Reads            | Passed in as `specification.vpc_config`                                                                        |
| API Gateway REST API            | terraform-aws-app-apigw-lambda      | Displays         | This module never sees the API's id; it only contributes the spec fragment                                     |
| Lambda invoke permission        | terraform-aws-app-apigw-lambda      | n/a              | Owned there to break the dependency cycle described above                                                      |

---

## External integrations

| System                                | Type             | Direction  | Notes                                                                                                                                                                                |
| ------------------------------------- | ---------------- | ---------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| terraform-aws-app-apigw-lambda        | Terraform module | ← inbound  | The primary consumer, and the one this repo's README points at. Instantiates this module with `for_each` over its `local.lambdas`, pinned `~> 1.0`, passing `name = each.key`        |
| Predecessor app module (private repo) | Terraform module | ← inbound  | The module apigw-lambda succeeded, still present and still pinned `~> 1.0`, so it also picks up any 1.x release. Treat both as live consumers until the owner confirms it is retired |
| Terraform Registry                    | Module registry  | → outbound | Published as `guidion-digital/helper-lambda/aws`; releases are tags cut by CI                                                                                                        |
| AWS (Lambda, EC2 security groups)     | Provider API     | → outbound | Via the caller's `aws` provider; this module declares no provider requirements of its own                                                                                            |
| terrappy (reusable workflows)         | GitHub Actions   | ← inbound  | `tfc-test-helper-module-plan.yaml@v1` and `tfc-test-helper-module-apply.yaml@v1` drive plan and apply tests                                                                          |
| release-workflows                     | GitHub Actions   | ← inbound  | `github-test-workflow`, `github-release-tag-dry-run`, `github-merge-into-master`, `github-release-tag`, all `@v2`                                                                    |
| LocalStack                            | Test target      | → outbound | The apply test runs against `environment_name: "localstack"`, not against real AWS                                                                                                   |
| HCP Terraform (`app.terraform.io`)    | Registry         | ← inbound  | Dependabot registry for Terraform dependency updates, authenticated with `TFC_PLANNER_API_TOKEN`                                                                                     |
| GitHub Dependabot                     | Automation       | ← inbound  | Daily GitHub Actions and Terraform update PRs, grouped minor/patch vs major                                                                                                          |

Direction legend:

- `→ outbound`: this system calls another system
- `← inbound`: another system calls this system
- `↔ bidirectional`: both systems exchange data

---

## APIs exposed

This module exposes no network endpoints. Its interface is its Terraform outputs, and the `paths_spec` output is itself a description of endpoints that the _caller_ will expose. Consumers listed below are verified against the checked-out `terraform-aws-app-apigw-lambda`.

| Endpoint / method                                                                    | Purpose                                                                                                 | Consumer                                                                                       |
| ------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------- |
| `output paths_spec`                                                                  | OpenAPI `paths` object for the caller's API Gateway `body`, including `x-amazon-apigateway-integration` | terraform-aws-app-apigw-lambda (`main.tf`, deep-merged across all Lambdas)                     |
| `output lambda_arn`                                                                  | Unqualified function ARN                                                                                | terraform-aws-app-apigw-lambda, passed to its `event_triggers` submodule                       |
| `output lambda_version`                                                              | Published version number                                                                                | terraform-aws-app-apigw-lambda, surfaced in its own outputs                                    |
| `output lambda_arn_for_permission`                                                   | Alias ARN when versioned, function ARN otherwise — the correct target for `aws_lambda_permission`       | **Not currently consumed by any known caller** (see Known risks)                               |
| `output lambda_invoke_arn`                                                           | Alias invoke ARN when versioned, function invoke ARN otherwise                                          | Not consumed by the API Lambda App module (it reads `paths_spec`, which embeds the same value) |
| `output lambda_function_name`, `lambda_qualified_arn`, `lambda_qualified_invoke_arn` | Convenience passthroughs                                                                                | No known consumer                                                                              |
| `output specification`                                                               | Echoes the resolved input back to the caller                                                            | Available via the whole-module passthrough the caller re-exports                               |

---

## APIs / services consumed

| Service                       | Purpose                                                                                                              | Authentication                                         |
| ----------------------------- | -------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------ |
| AWS Lambda API                | Create function, publish version, create alias                                                                       | Caller's `aws` provider credentials (IAM role or keys) |
| AWS EC2 API (security groups) | Create security group and ingress/egress rules when `vpc_enabled`                                                    | Caller's `aws` provider credentials                    |
| AWS STS                       | `data.aws_caller_identity.current` is declared but never referenced; it still forces an `sts:GetCallerIdentity` call | Caller's `aws` provider credentials                    |
| `hashicorp/archive` provider  | Build the deployment zip locally                                                                                     | None (local operation)                                 |
| LocalStack                    | Target for the CI apply test                                                                                         | Provided by the Terrappy reusable workflow             |
| HCP Terraform registry        | Dependabot Terraform dependency lookups                                                                              | `secrets.TFC_PLANNER_API_TOKEN`                        |

---

## Module interface contract

Added because this repo is a registry-published module: for a module, the input/output surface _is_ the architecture, and a change here is a change to every consumer's plan. This table separates the load-bearing surface from the vestigial parts, so a future change knows what it is allowed to touch.

| Surface                                                                       | Status                         | Contract                                                                                                                                                                                                                              |
| ----------------------------------------------------------------------------- | ------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `var.name`                                                                    | Load-bearing, non-obvious      | Names the zip artefact (`${path.module}/${var.name}.zip`), nothing in AWS. It **must be unique per instantiation within a root module**, or two instances write to the same zip path. The caller satisfies this by passing `each.key` |
| `var.application_name`                                                        | **Vestigial but required**     | Declared with no type and no default, so callers must pass it, and it is referenced nowhere in the module. Removing it is a breaking change for callers; leaving it misleads readers                                                  |
| `var.tags`                                                                    | Load-bearing                   | Required, untyped as a map; applied to the function and the security-group rules                                                                                                                                                      |
| `specification.function_name`, `role_arn`, `runtime`, `handler`, `source_dir` | Load-bearing, required         | No defaults; the module fails without them                                                                                                                                                                                            |
| `specification.latest_version_alias`                                          | **Cross-repo naming contract** | This module names the alias from it; terraform-aws-app-apigw-lambda independently sets its `aws_lambda_permission.qualifier` from its own copy of the same value. Changing this default breaks invoke permissions in the caller       |
| `specification.publish_version`                                               | Load-bearing                   | Defaults true. Switches four outputs between alias-qualified and unqualified values, and gates alias creation                                                                                                                         |
| `specification.vpc_enabled`                                                   | **Narrower than its name**     | Gates security-group creation only, not VPC attachment (see Known risks)                                                                                                                                                              |
| `specification.endpoints`                                                     | Load-bearing                   | Nested `map(map(object(...)))`: endpoint name → method key → method config. Attributes not in the declared type are **silently discarded** by Terraform, not rejected                                                                 |
| `output paths_spec`, `lambda_arn`, `lambda_version`                           | Load-bearing                   | Consumed by terraform-aws-app-apigw-lambda; renaming or reshaping breaks it                                                                                                                                                           |
| `output lambda_arn_for_permission`                                            | Shipped, unconsumed            | Added in `e791f57` for correctness; the caller has not adopted it                                                                                                                                                                     |
| Registry version line                                                         | Load-bearing                   | Consumer pins `~> 1.0` and tag `1.0.0` sits at HEAD, so any 1.x tag CI cuts is picked up automatically. A breaking change needs a 2.x tag, not a 1.x one                                                                              |
| Provider requirements                                                         | **Undeclared**                 | No `terraform {}` block anywhere in the repo: no `required_version`, no `required_providers`. The `archive` provider dependency is satisfied only because callers happen to have it                                                   |

---

## Deployment

**CI/CD:** GitHub Actions, delegating to reusable workflows in `guidion-digital/terrappy` (`@v1`) and `guidion-digital/release-workflows` (`@v2`).

**Infra:** No deployed infrastructure. The artefact is a Terraform Registry module version, cut as a git tag.

**Branch strategy:** `acc` is the repository default branch and the PR target — not `master`. `.github/workflows/test-plan.yaml` runs on PRs into `acc` (plan test plus a release dry-run). On push to `acc`, `.github/workflows/test-apply-and-release.yaml` runs the LocalStack apply test, then merges `acc` into `master` and cuts a release tag. `master` is therefore a downstream mirror of released state, not the integration branch.

**Environments:**

- `localstack` — the only environment the module is exercised in by CI
- Consumer accounts — wherever a caller's provider points; this repo has no visibility into them

How release gating actually works, since a green run does not mean the module was tested:

- **The whole test-and-release chain is gated on Terraform files having changed.** In the Terrappy apply workflow, `dorny/paths-filter` matches `**/*.tf` and sets `terraform-file-changes-result`; the example-matrix job runs only when that is `'true'`, so the LocalStack apply is _skipped_ — not failed — for any change that touches no `.tf` file. That is what the caller's two mutually exclusive jobs encode: `workflow-change` merges `acc` into `master` without cutting a tag on the skipped path, and `terraform-module-change` plus `release-module-version` cut a tag only when the apply actually reported `success`. A failed apply satisfies neither condition, so nothing merges.
- **The consequence to remember is which changes cannot produce a release**, rather than any gap in the gating: edits to an example's Python payload, to the workflows, or to documentation merge into `master` with no new module version. Conversely, editing only `examples/test_app/main.tf` does trigger a full apply and a release tag, even though the module itself is unchanged.
- **The apply matrix is every directory under `./examples`.** `examples/test_app` is therefore the CI fixture — changing it changes what CI proves — and adding an example directory adds an apply target that must succeed for any release to be cut.

---

## Architectural notes and key decisions

- **Versioning and aliasing were added deliberately, and they reshape the output surface.** `c2620ee`, `5dc2c55`, `1e8a741`, `e791f57` and `17d45aa` moved the module from unversioned functions to published versions behind a configurable alias. The consequence is that `lambda_invoke_arn` and `lambda_arn_for_permission` are conditional on `publish_version`: when it is true they return the _alias_, so anything downstream that invokes or grants must use the qualified value.
- **Invoke permission lives in the caller on purpose.** A comment in terraform-aws-app-apigw-lambda spells out the cycle: the REST API is built from an OpenAPI `body` that must already contain the Lambda ARN, so `source_arn` for the permission cannot be known inside this module. The caller constructs the `execute-api` ARN by hand instead.
- **`data.archive_file` must not be a `depends_on` target.** `7fd89de` ("Fixed always-redploy bug") moved the `archive_file` data source below the security-group resources and removed `depends_on = [data.archive_file.this]` from the function. With that `depends_on` present, the data source could only be read during apply, leaving `source_code_hash` unknown at plan time and redeploying the Lambda on every run. Do not reintroduce a `depends_on` pointing at that data source.
- **The same commit fixed one `== {}` comparison and not the other.** `environment == {}` became a `length() > 0` check; `vpc_config == {}` at `main.tf:66` was left as-is. Comparing an object against an empty map literal is never true in Terraform, so that guard has never fired (see Known risks).
- **`mock` integrations get CORS headers filled in for you.** `outputs.tf` special-cases `integration.type == "mock"`: it merges in `Access-Control-Allow-Origin/Methods/Headers`, forces a `{statusCode:200}` request template and `CONVERT_TO_TEXT` content handling, and collapses responses to a single `default`. A mock integration can therefore only express one response code.
- **`AccessControlAllowMethods` is an intentional shortcut**, documented in-repo as a "cheat" — it lets a caller set the allowed-methods header without spelling out `responses.headers`. When omitted, the value is derived by joining every method across every endpoint in the `endpoints` map, which is only correct when the endpoint is defined by a single Lambda; with several Lambdas contributing to one path, the caller's deep-merge keeps only the last.
- **The zip is written inside the module directory.** `output_path = "${path.module}/${var.name}.zip"` means artefacts land next to the module source — in `.terraform/modules/...` for registry consumers, and directly in this repo's root for local example runs. That is why untracked `*.zip` files appear at the repo root after running the example; `.gitignore` covers them.
- **Input validation is deliberately absent.** A commented-out `validation` block in `variables.tf` carries a TODO explaining why: the `optional()` defaults throughout the `specification` object defeat a generic "no null mandatory fields" check.

---

## Known risks / fragile areas

- **`vpc_enabled` gates security-group creation, not VPC attachment.** The security group is conditional on `var.specification.vpc_enabled` (`main.tf:7`), but the `dynamic "vpc_config"` block on the function is conditional on `var.specification.vpc_config == {}` (`main.tf:66`). A caller that passes `vpc_config` while setting `vpc_enabled = false` gets a Lambda attached to those subnets with **no module-created security group**. terraform-aws-app-apigw-lambda passes `this_lambda_value.vpc_config` through in exactly that branch, so the combination is reachable from the primary consumer.
- **The `vpc_config == {}` guard is dormant, not merely suspect.** Two things are verified by test: the comparison is `false` even for the default value, so the `dynamic` block always renders; and the AWS provider accepts the all-empty block and includes a `vpc_config` block in the plan. The apply-time effect is **not** verified — the example's applied state records `vpc_config = []`, which suggests no attachment actually lands, but that state is untracked and predates HEAD, so treat it as weak evidence rather than proof. Either way the guard never fires: `vpc_config` is never switched off, only emptied.
- **`vpc_id` is a list and is indexed unguarded.** `vpc_id = var.specification.vpc_config.vpc_id[0]` (`main.tf:10`) reads element 0 of a list that defaults to `[]`. Setting `vpc_enabled = true` without a `vpc_config.vpc_id` fails with an index-out-of-range error rather than a readable validation message.
- **A caller granting invoke permission on `lambda_arn` while versioning is on will get 403s.** With `publish_version = true` the OpenAPI integration URI is the _alias_ invoke ARN, so the permission must carry the alias qualifier. `lambda_arn_for_permission` exists for this, but is unconsumed: terraform-aws-app-apigw-lambda instead sets `qualifier` from its own copy of `latest_version_alias`. Any other caller that wires `aws_lambda_permission` to `lambda_arn` is granting on the wrong qualifier.
- **`httpMethod` in the integration extension reads backwards, but the branch that matters is the correct one.** `outputs.tf:97` reads `httpMethod = this_method_config.http_method == null ? "POST" : null`: it emits `POST` when the caller sets nothing, and `null` when the caller _does_ set `http_method`. `POST` is the right value for an `aws_proxy` integration — the extension's `httpMethod` is the _integration's_ method, always `POST` for Lambda proxy, not the route's method — so the default path is correct. Neither terraform-aws-app-apigw-lambda nor its predecessor sets `http_method` anywhere: the field is declared `optional(string)` in the caller's endpoint schema, is undocumented in its README, and is read by nothing except this ternary. **Effect on the live caller today: none.** The null branch is reachable only by a consumer that sets that declared-but-undocumented field.
- **When the null branch _is_ reached, the null reaches API Gateway verbatim.** Verified by running the caller's own merge path (`yamlencode` → `cloudposse/utils` `utils_deep_merge_yaml` → `yamldecode` → `jsonencode`): `"httpMethod": null` survives into the REST API body unchanged rather than being dropped. What API Gateway then does with it is unverified, but the caller carries a standing TODO noting that the body resource "accepts and ignores invalid _parts_ of the body", so a silently integration-less method is the likely outcome rather than a plan-time error. Two readings of the intent are open — "never let a route method leak into the integration method, so emit nothing" versus a mis-written override that should have been `: this_method_config.http_method` — and the fix differs between them. Settle intent with the owner before changing it; the low-risk change is to reject or ignore `http_method` explicitly rather than to start emitting it.
- **Unknown attributes in `endpoints` are silently discarded.** Terraform drops attributes absent from an `object()` type constraint rather than erroring — verified by test. The example's own method-level `headers` block (`examples/test_app/main.tf:60`) is not part of the declared type at `variables.tf:54` and is thrown away; only `responses.headers` is real. A caller can add configuration that appears accepted and does nothing.
- **The default egress rule is fully open.** When `vpc_enabled` is true and no `security_group_rules.egress` is supplied, `variables.tf` defaults to protocol `-1` to `0.0.0.0/0`. That is conventional for Lambda egress but is a wide default arriving without the caller asking for it.
- **`var.name` must be unique per root module.** Two instances sharing a `name` write to the same `${path.module}/<name>.zip`. The consumer's `name = each.key` avoids this; a hand-written caller can trip it.
- **No provider or Terraform version constraints.** Adding a `required_providers` block is a compatibility decision for every consumer, so it needs a deliberate release, but its absence means the module's `archive` dependency is undeclared and nothing pins the AWS provider major.
- **`application_name` is required and unused.** Do not "clean it up" casually: removing an input is a breaking change for callers that pass it, including terraform-aws-app-apigw-lambda.
- **Releasing is automatic once a PR is merged, so the PR review _is_ the release gate.** `acc` is a protected branch — consult its settings in GitHub for the current rules rather than inferring them from the workflow files. There is no separate approval step between a merge and a published 1.x tag, so the release implications of a change have to be weighed at PR-review time. Consumers pinning `~> 1.0` then pick the new version up on any fresh `terraform init` — module versions are not recorded in `.terraform.lock.hcl`, which locks providers only, so a CI runner with no cached `.terraform/` resolves the newest matching 1.x every run, while a local working copy holds its resolved version until `terraform init -upgrade`.
- **`httpMethod` (`outputs.tf:97`) override for API integration method is permitted** This makes sense since the `x-amazon-apigateway-integration` `type` can also be set in this module. It should be noted however, that setting this to anything other than `POST` will break the main way the module is intended to be used (with Lambdas)

---

## AI assistant guidance

When modifying this repo:

- **Open PRs against `acc`, never `master`.** `master` is the released mirror; CI merges into it and tags from `acc`.
- **Treat every input and output as a published interface.** This module is on the public Terraform Registry and its consumer pins `~> 1.0`. Renaming or removing an input or output is a breaking change requiring a major version, even when the value looks unused inside this repo.
- **Do not add a `depends_on` referencing `data.archive_file.this`.** That is the exact cause of the always-redeploy bug fixed in `7fd89de`.
- **Never compare an object to `{}` in Terraform.** It is always false. Use `length()`, `== null`, or an explicit boolean flag. The `vpc_config` guard is the surviving example of this mistake.
- **Prefer adding an explicit boolean or a `validation` block over inferring intent from an empty collection.** The `vpc_enabled`-versus-`vpc_config` split is what happens otherwise.
- **Do not change `latest_version_alias`'s default, the alias resource's name derivation, or the `publish_version` conditionals in `outputs.tf` without checking terraform-aws-app-apigw-lambda.** That repo derives its `aws_lambda_permission.qualifier` from the same value independently; the two must agree.
- **`paths_spec` is consumed by deep-merge across several Lambdas.** Anything that assumes an endpoint is described by exactly one Lambda — the derived `Access-Control-Allow-Methods` value especially — can silently lose data when merged.
- **Test changes through `examples/test_app`**, which is the CI fixture, and remember that CI applies against LocalStack: a green run is not evidence that API Gateway accepts the emitted OpenAPI spec.
- **Ask for architecture review before** changing the module's input/output surface, the versioning/alias behaviour, the VPC and security-group logic, or where invoke permission is granted.

If this file contradicts the actual code, the code wins — flag the discrepancy to the repo owner instead of trusting the doc

---

## Roadmap / active migrations

No migration is in flight. The items below are known gaps recorded here so they are decided rather than rediscovered; none is scheduled.

- [ ] Decide the intended `vpc_enabled` semantics and make attachment and security-group creation agree (owner decision: does `vpc_enabled = false` mean "never attach"?)
- [ ] Adopt `lambda_arn_for_permission` in terraform-aws-app-apigw-lambda, or document that callers must qualify permissions themselves
- [ ] Add a `terraform {}` block with `required_version` and `required_providers` (`aws`, `archive`) — needs a release decision, as it constrains consumers
- [ ] Decide whether `application_name` is removed in a future major or documented as reserved
- [ ] Replace the commented-out `validation` block with targeted validations (`vpc_enabled` implies non-empty `vpc_config.vpc_id`, for one)

---

## Freshness

- **Last reviewed:** 2026-09-09
- **Review confidence:** low
- **Generated by:** AI-assisted
- **Validated by:** none
- **Update when:** integrations change, stack changes, exposed APIs change, data ownership changes, or a relevant architectural decision is made

Coverage of this generation, so a reader knows what is asserted from reading versus inferred: every tracked file in this repo was read in full — `main.tf`, `variables.tf`, `outputs.tf`, `README.md`, both workflow files, `.github/CODEOWNERS`, `.github/dependabot.yml`, `.gitignore`, `.detect-secrets.baseline`, and all of `examples/test_app`. The full commit history (10 commits) was read, and `git log -S` used to date the `vpc_config == {}` and `httpMethod` expressions to the initial release. Three behavioural claims were verified by running Terraform rather than asserted: that an object never equals `{}` and the `vpc_config` block therefore always renders, that the AWS provider accepts and normalises an all-empty `vpc_config`, and that Terraform silently discards object attributes absent from a type constraint. A fourth was verified by running the caller's actual merge path with the `cloudposse/utils` provider: a null `httpMethod` survives `yamlencode` → deep merge → `yamldecode` → `jsonencode` into the API body unchanged. The consumer relationship was verified against local checkouts of both terraform-aws-app-apigw-lambda (the current caller, per this repo's README) and the private predecessor module it succeeded, so consumer statements are accurate as of those checkouts and not necessarily as of their `HEAD`s. Nothing in this repo was characterised only structurally. Confidence is `low` because no human has validated it, which is the correct state for a first generation regardless of how the draft was produced.
