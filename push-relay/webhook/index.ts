import type { HttpRequest, InvocationContext, HttpResponseInit } from "@azure/functions";

export default async function webhook(
  request: HttpRequest,
  context: InvocationContext,
): Promise<HttpResponseInit> {
  context.log("Received BC webhook placeholder", {
    method: request.method,
    url: request.url,
  });

  return {
    status: 200,
    jsonBody: {
      ok: true,
    },
  };
}

