/**
 * Import function triggers from their respective submodules:
 *
 * const {onCall} = require("firebase-functions/v2/https");
 * const {onDocumentWritten} = require("firebase-functions/v2/firestore");
 *
 * See a full list of supported triggers at https://firebase.google.com/docs/functions
 */

/**
 * Import function triggers from their respective submodules:
 *
 * const {onCall} = require("firebase-functions/v2/https");
 * const {onDocumentWritten} = require("firebase-functions/v2/firestore");
 *
 * See a full list of supported triggers at https://firebase.google.com/docs/functions
 */

/**
 * Import function triggers from their respective submodules:
 *
 * const {onCall} = require("firebase-functions/v2/https");
 * const {onDocumentWritten} = require("firebase-functions/v2/firestore");
 *
 * See a full list of supported triggers at https://firebase.google.com/docs/functions
 */

const {setGlobalOptions} = require("firebase-functions");
setGlobalOptions({maxInstances: 10});

const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {defineSecret} = require("firebase-functions/params");
const logger = require("firebase-functions/logger");

const OPENAI_API_KEY = defineSecret("OPENAI_API_KEY");

/**
 * Extracts the generated text from an OpenAI Responses API payload.
 *
 * Handles multiple response formats and safely concatenates all textual output.
 *
 * @param {Object} json - Raw JSON response returned by OpenAI Responses API
 * @return {string} Extracted assistant text (may be empty)
 */
function extractResponseText(json) {
  if (json && typeof json.output_text === "string" && json.output_text) {
    return json.output_text;
  }

  const outputs = (json && Array.isArray(json.output)) ? json.output : [];
  const parts = [];

  for (const out of outputs) {
    const content = (out && Array.isArray(out.content)) ? out.content : [];
    for (const c of content) {
      if (!c) continue;

      // Most common: {type:"output_text", text:"..."}
      if (typeof c.text === "string" && c.text) {
        parts.push(c.text);
        continue;
      }

      // Some SDK variants may nest it
      if (c.type === "output_text" && typeof c.text === "string") {
        parts.push(c.text);
      }
      if (c.type === "summary_text" && typeof c.text === "string") {
        parts.push(c.text);
      }
    }
  }

  return parts.join("").trim();
}

exports.openaiProxy = onCall(
    {
      region: "us-central1",
      secrets: [OPENAI_API_KEY],
    },
    async (request) => {
      try {
        // Auth disabled (per your request)
        // if (!request.auth) {
        //     throw new HttpsError("unauthenticated", "Must be signed in.");
        // }

        const data = request.data || {};
        const prompt = String(data.prompt || "").trim();

        if (!prompt) {
          throw new HttpsError("invalid-argument", "Missing 'prompt'.");
        }
        if (prompt.length > 4000) {
          throw new HttpsError("invalid-argument", "Prompt too long.");
        }

        const modelFromReq = String(data.model || "").trim();
        const model = modelFromReq || "gpt-4.1-mini";

        const temperature =
                typeof data.temperature === "number" ? data.temperature : 0.2;

        const apiKey = OPENAI_API_KEY.value();
        if (!apiKey) {
          throw new HttpsError(
              "failed-precondition",
              "Missing OPENAI_API_KEY secret.",
          );
        }

        const body = {
          model: model,
          input: [
            {
              role: "system",
              content: [
                {
                  type: "input_text",
                  text: "You are a helpful assistant.",
                },
              ],
            },
            {
              role: "user",
              content: [
                {
                  type: "input_text",
                  text: prompt,
                },
              ],
            },
          ],
          temperature: temperature,
        };

        const resp = await fetch("https://api.openai.com/v1/responses", {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "Authorization": "Bearer " + apiKey,
          },
          body: JSON.stringify(body),
        });

        const json = await resp.json();

        if (!resp.ok) {
          logger.error("OpenAI error", {
            status: resp.status,
            json: json,
          });

          throw new HttpsError(
              "internal",
              "OpenAI request failed",
              {
                status: resp.status,
                error: json,
              },
          );
        }

        // const text =
        //         typeof json.output_text === "string" ? json.output_text : "";

        const text = extractResponseText(json);

        return {
          ok: true,
          text: text,
          model: json.model || model,
          usage: json.usage || null,
        };
      } catch (err) {
        if (err instanceof HttpsError) {
          throw err;
        }

        logger.error("openaiProxy crashed", err);

        throw new HttpsError(
            "internal",
            "Server error",
            {
              message:
                        err && err.message ? err.message : String(err),
            },
        );
      }
    },
);
