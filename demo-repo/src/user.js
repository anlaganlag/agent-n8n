export function isValidEmail(email) {
  return typeof email === "string" && email.includes("@");
}

export function createUser(input) {
  return {
    status: 201,
    body: {
      email: input.email
    }
  };
}
