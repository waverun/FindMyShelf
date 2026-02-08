/* eslint-disable max-len */
/* eslint-disable require-jsdoc */

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
                                     if (!request.auth) {
                                         throw new HttpsError("unauthenticated", "Must be signed in.");
                                     }

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

                                     const resp = await fetch(
                                                              "https://api.openai.com/v1/responses",
                                                              {
                                                              method: "POST",
                                                              headers: {
                                                                  "Content-Type": "application/json",
                                                                  "Authorization": "Bearer " + apiKey,
                                                              },
                                                              body: JSON.stringify(body),
                                                              },
                                                              );

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

/**
 * OCR an image using OpenAI (Responses API).
 *
 * Input:
 * {
 *   image: { mime: "image/jpeg", base64: "...", detail: "high" | "low" },
 *   model?: string
 * }
 *
 * Output:
 * { ok: true, text: string, lines: string[], language: string|null }
 *
 * @param {Object} request - Callable request
 * @return {Promise<Object>} response object
 */
exports.openaiOcrProxy = onCall(
                                {
                                region: "us-central1",
                                secrets: [OPENAI_API_KEY],
                                },
                                async (request) => {
                                    try {
                                        if (!request.auth) {
                                            throw new HttpsError("unauthenticated", "Must be signed in.");
                                        }

                                        const data = request.data || {};
                                        const image = data.image;

                                        if (!image || typeof image !== "object") {
                                            throw new HttpsError("invalid-argument", "Missing 'image'.");
                                        }

                                        const mime = (typeof image.mime === "string") ?
                                        image.mime.trim() :
                                        "";
                                        const b64 = (typeof image.base64 === "string") ?
                                        image.base64.trim() :
                                        "";

                                        const detail =
                                        (image.detail === "low" || image.detail === "high") ?
                                        image.detail :
                                        "high";

                                        if (!mime || !b64) {
                                            throw new HttpsError(
                                                                 "invalid-argument",
                                                                 "image.mime and image.base64 are required.",
                                                                 );
                                        }

                                        // 8MB base64 ~= ~6MB binary-ish. Adjust if you need.
                                        if (b64.length > 8000000) {
                                            throw new HttpsError("invalid-argument", "Image too large.");
                                        }

                                        const modelFromReq = (typeof data.model === "string") ?
                                        data.model.trim() :
                                        "";
                                        const model = modelFromReq || "gpt-4.1-mini";

                                        const apiKey = OPENAI_API_KEY.value();
                                        if (!apiKey) {
                                            throw new HttpsError(
                                                                 "failed-precondition",
                                                                 "Missing OPENAI_API_KEY secret.",
                                                                 );
                                        }

                                        const systemText =
                                        "You are an OCR engine. Extract exactly what is visible.";

                                        const userText =
                                        "Return ONLY valid JSON with keys: " +
                                        "text (string), lines (array of strings), language (string|null). " +
                                        "Rules: " +
                                        "1) Extract all visible text even if partial or imperfect. " +
                                        "2) Preserve the original script (do not translate). " +
                                        "3) lines should follow reading order when possible. " +
                                        "4) If text is unclear, return your BEST GUESS (do not return empty unless truly no text is visible).";
                                        // const userText =
                                        // "Return ONLY valid JSON with keys: " +
                                        // "text (string), lines (array of strings), language (string|null). " +
                                        // "Rules: " +
                                        // "1) Preserve the original script (do not translate). " +
                                        // "2) lines must be in reading order, one printed line per item. " +
                                        // "3) If unsure, return empty text and empty lines.";

                                        const imageUrl = [
                                            "data:",
                                            mime,
                                            ";base64,",
                                            b64,
                                        ].join("");

                                        const body = {
                                            model: model,
                                            input: [
                                                {
                                                role: "system",
                                                content: [
                                                          {type: "input_text", text: systemText},
                                                          ],
                                                },
                                                {
                                                role: "user",
                                                content: [
                                                    {type: "input_text", text: userText},
                                                    {
                                                    type: "input_image",
                                                    image_url: imageUrl,
                                                    detail: detail,
                                                    },
                                                ],
                                                },
                                            ],
                                            temperature: 0.0,
                                        };

                                        const resp = await fetch(
                                                                 "https://api.openai.com/v1/responses",
                                                                 {
                                                                 method: "POST",
                                                                 headers: {
                                                                     "Content-Type": "application/json",
                                                                     "Authorization": "Bearer " + apiKey,
                                                                 },
                                                                 body: JSON.stringify(body),
                                                                 },
                                                                 );

                                        const json = await resp.json();

                                        if (!resp.ok) {
                                            logger.error("OpenAI OCR error", {
                                                status: resp.status,
                                                json: json,
                                            });

                                            throw new HttpsError(
                                                                 "internal",
                                                                 "OpenAI OCR request failed",
                                                                 {
                                                                 status: resp.status,
                                                                 error: json,
                                                                 },
                                                                 );
                                        }

                                        const raw = extractResponseText(json).trim();
                                        if (!raw) {
                                            return {
                                                ok: true,
                                                text: "",
                                                lines: [],
                                                language: null,
                                            };
                                        }

                                        let parsed = null;
                                        try {
                                            parsed = JSON.parse(raw);
                                        } catch (e) {
                                            // If the model returns non-JSON, fail loudly (debuggable).
                                            throw new HttpsError(
                                                                 "internal",
                                                                 "OCR returned non-JSON output",
                                                                 {raw: raw},
                                                                 );
                                        }

                                        const text =
                                        (parsed && typeof parsed.text === "string") ?
                                        parsed.text :
                                        "";

                                        const lines =
                                        (parsed && Array.isArray(parsed.lines)) ?
                                        parsed.lines.filter((x) => typeof x === "string") :
                                        [];

                                        const language =
                                        (parsed && typeof parsed.language === "string") ?
                                        parsed.language :
                                        null;

                                        return {
                                            ok: true,
                                            text: text,
                                            lines: lines,
                                            language: language,
                                        };
                                    } catch (err) {
                                        if (err instanceof HttpsError) throw err;

                                        logger.error("openaiOcrProxy crashed", err);

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

exports.openaiAisleVisionProxy = onCall(
                                        {
                                        region: "us-central1",
                                        secrets: [OPENAI_API_KEY],
                                        },
                                        async (request) => {
                                            try {
                                                if (!request.auth) {
                                                    throw new HttpsError("unauthenticated", "Must be signed in.");
                                                }

                                                const data = request.data || {};
                                                const image = data.image;

                                                if (!image || typeof image !== "object") {
                                                    throw new HttpsError("invalid-argument", "Missing 'image'.");
                                                }

                                                const mime = typeof image.mime === "string" ? image.mime.trim() : "";
                                                const b64 = typeof image.base64 === "string" ? image.base64.trim() : "";
                                                const detail = image.detail === "low" || image.detail === "high" ?
                                                image.detail :
                                                "high";

                                                if (!mime || !b64) {
                                                    throw new HttpsError(
                                                                         "invalid-argument",
                                                                         "image.mime and image.base64 are required.",
                                                                         );
                                                }

                                                const modelFromReq = typeof data.model === "string" ? data.model.trim() : "";
                                                const model = modelFromReq || "gpt-5.2";

                                                const apiKey = OPENAI_API_KEY.value();
                                                if (!apiKey) {
                                                    throw new HttpsError(
                                                                         "failed-precondition",
                                                                         "Missing OPENAI_API_KEY secret.",
                                                                         );
                                                }

                                                const systemText =
                                                "You extract aisle info from grocery aisle-sign images.";

                                                const userText =
                                                "Return ONLY valid JSON with keys: " +
                                                "title_original (string|null), title_en (string|null), " +
                                                "aisle_code (string|null), keywords_original (array of strings), " +
                                                "keywords_en (array of strings). " +
                                                "Rules: " +
                                                "1) keywords should be short and useful. " +
                                                "2) Do not invent brands not seen. " +
                                                "3) If Hebrew exists, put it in title_original/keywords_original. " +
                                                "4) If English exists, put it in title_en/keywords_en. " +
                                                "5) If there is a clear aisle code/number (like 'A12'), put it in aisle_code.";

                                                const imageUrl = ["data:", mime, ";base64,", b64].join("");

                                                const body = {
                                                    model,
                                                    input: [
                                                        {
                                                        role: "system",
                                                        content: [{type: "input_text", text: systemText}],
                                                        },
                                                        {
                                                        role: "user",
                                                        content: [
                                                            {type: "input_text", text: userText},
                                                            {type: "input_image", image_url: imageUrl, detail},
                                                        ],
                                                        },
                                                    ],
                                                    temperature: 0.0,
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
                                                    logger.error("OpenAI AisleVision error", {status: resp.status, json});
                                                    throw new HttpsError("internal", "OpenAI request failed", {
                                                        status: resp.status,
                                                        error: json,
                                                    });
                                                }

                                                const raw = extractResponseText(json).trim();
                                                if (!raw) {
                                                    throw new HttpsError("internal", "Aisle vision returned empty output");
                                                }

                                                let parsed;
                                                try {
                                                    parsed = JSON.parse(raw);
                                                } catch (e) {
                                                    throw new HttpsError("internal", "Aisle vision returned non-JSON", {
                                                        raw,
                                                    });
                                                }

                                                // Sanitize
                                                const result = {
                                                    title_original: typeof parsed.title_original === "string" ?
                                                    parsed.title_original :
                                                    null,
                                                    title_en: typeof parsed.title_en === "string" ? parsed.title_en : null,
                                                    aisle_code: typeof parsed.aisle_code === "string" ? parsed.aisle_code : null,
                                                    keywords_original: Array.isArray(parsed.keywords_original) ?
                                                    parsed.keywords_original.filter((x) => typeof x === "string") :
                                                    [],
                                                    keywords_en: Array.isArray(parsed.keywords_en) ?
                                                    parsed.keywords_en.filter((x) => typeof x === "string") :
                                                    [],
                                                };

                                                return {ok: true, result};
                                            } catch (err) {
                                                if (err instanceof HttpsError) throw err;
                                                logger.error("openaiAisleVisionProxy crashed", err);
                                                throw new HttpsError("internal", "Server error", {
                                                    message: err && err.message ? err.message : String(err),
                                                });
                                            }
                                        },
                                        );
