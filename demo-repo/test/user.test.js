import test from "node:test";
import assert from "node:assert/strict";

import { createUser, isValidEmail } from "../src/user.js";

test("isValidEmail returns true for a basic valid email", () => {
  assert.equal(isValidEmail("dev@example.com"), true);
});

test("createUser returns 201 for valid email", () => {
  const result = createUser({ email: "dev@example.com" });
  assert.equal(result.status, 201);
  assert.equal(result.body.email, "dev@example.com");
});

test("createUser returns 400 for invalid email", () => {
  const result = createUser({ email: "bad-email" });
  assert.equal(result.status, 400);
  assert.deepEqual(result.body, { error: "invalid email" });
});
