const crypto = require("node:crypto");
const admin = require("firebase-admin");
const { onRequest } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");

admin.initializeApp();

const openAiApiKey = defineSecret("OPENAI_API_KEY");

const REGION = "europe-west1";
const MODEL = "gpt-5.4-mini";
const WEEKLY_LIMIT = 10;
const MAX_RESULTS = 60;

exports.interpretResults = onRequest(
  {
    region: REGION,
    cors: true,
    secrets: [openAiApiKey],
    timeoutSeconds: 60,
    memory: "256MiB",
  },
  async (req, res) => {
    if (req.method !== "POST") {
      res.status(405).json({ error: "Method not allowed." });
      return;
    }

    try {
      const body = req.body || {};
      const installationId = cleanString(body.installationId, 96);
      const templateTitle = cleanString(body.templateTitle, 160);
      const results = normalizeResults(body.results);

      if (!installationId) {
        res.status(400).json({ error: "Missing installation id." });
        return;
      }
      if (!templateTitle) {
        res.status(400).json({ error: "Missing template results." });
        return;
      }
      if (results.length === 0) {
        res.status(400).json({ error: "Missing template results." });
        return;
      }

      const usage = await reserveWeeklyUse(installationId);
      const prompt = buildPrompt(templateTitle, results);
      const text = await generateOpenAiText(prompt);

      res.status(200).json({
        text,
        model: MODEL,
        weeklyLimit: WEEKLY_LIMIT,
        remaining: Math.max(0, WEEKLY_LIMIT - usage.count),
        resetAt: usage.resetAt,
      });
    } catch (error) {
      console.error(error);
      const status = error.statusCode || 500;
      res.status(status).json({
        error: error.publicMessage || "Could not generate interpretation.",
        resetAt: error.resetAt,
      });
    }
  },
);

async function reserveWeeklyUse(installationId) {
  const weekId = currentWeekId();
  const safeId = crypto
    .createHash("sha256")
    .update(`${installationId}:${weekId}`)
    .digest("hex");
  const ref = admin.firestore().collection("aiUsage").doc(safeId);

  return admin.firestore().runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    const currentCount = snapshot.exists ? snapshot.data().count || 0 : 0;
    if (currentCount >= WEEKLY_LIMIT) {
      const error = new Error("Weekly limit reached.");
      error.statusCode = 429;
      error.resetAt = nextWeeklyResetIso();
      error.publicMessage =
        `Weekly OrthoQuant AI limit reached. Your quota resets on ${formatResetDate(error.resetAt)}.`;
      throw error;
    }

    const nextCount = currentCount + 1;
    transaction.set(
      ref,
      {
        installationHash: crypto
          .createHash("sha256")
          .update(installationId)
          .digest("hex"),
        weekId,
        count: nextCount,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    return { count: nextCount, weekId, resetAt: nextWeeklyResetIso() };
  });
}

async function generateOpenAiText(prompt) {
  const response = await fetch("https://api.openai.com/v1/responses", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${openAiApiKey.value()}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: MODEL,
      input: prompt,
      max_output_tokens: 700,
    }),
  });

  const body = await response.json().catch(() => ({}));
  if (!response.ok) {
    const error = new Error("OpenAI request failed.");
    error.statusCode = response.status >= 400 && response.status < 500 ? 502 : 500;
    error.publicMessage =
      body.error && body.error.message
        ? body.error.message
        : "OpenAI request failed.";
    throw error;
  }

  if (typeof body.output_text === "string" && body.output_text.trim()) {
    return body.output_text.trim();
  }

  const chunks = [];
  if (Array.isArray(body.output)) {
    for (const item of body.output) {
      if (!Array.isArray(item.content)) continue;
      for (const part of item.content) {
        if (typeof part.text === "string" && part.text.trim()) {
          chunks.push(part.text.trim());
        }
      }
    }
  }

  const text = chunks.join("\n").trim();
  if (text) return text;

  const error = new Error("Empty model response.");
  error.statusCode = 502;
  error.publicMessage = "The model returned an empty response.";
  throw error;
}

function buildPrompt(templateTitle, results) {
  const formattedResults = results
    .map((item) => `- ${item.label}: ${item.value}`)
    .join("\n");

  return `You are assisting an orthopedic clinician inside a measurement app.

Template: ${templateTitle}
Measurements:
${formattedResults}

Explain in English what these measurements may clinically indicate. Keep it concise and practical. Do not diagnose. Do not recommend treatment. Mention that interpretation depends on patient age, symptoms, imaging quality, projection, and clinical context when relevant.`;
}

function normalizeResults(value) {
  if (!Array.isArray(value)) return [];
  return value
    .slice(0, MAX_RESULTS)
    .map((item) => ({
      label: cleanString(item && item.label, 120) || "Measurement",
      value: cleanString(item && item.value, 120),
    }))
    .filter((item) => item.value);
}

function cleanString(value, maxLength) {
  return typeof value === "string" ? value.trim().slice(0, maxLength) : "";
}

function currentWeekId() {
  const now = new Date();
  const day = now.getUTCDay() || 7;
  const monday = new Date(
    Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()),
  );
  monday.setUTCDate(monday.getUTCDate() - day + 1);
  return monday.toISOString().slice(0, 10);
}

function nextWeeklyResetIso() {
  const now = new Date();
  const day = now.getUTCDay() || 7;
  const nextMonday = new Date(
    Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()),
  );
  nextMonday.setUTCDate(nextMonday.getUTCDate() - day + 8);
  return nextMonday.toISOString();
}

function formatResetDate(isoValue) {
  return new Intl.DateTimeFormat("en", {
    dateStyle: "medium",
    timeStyle: "short",
    timeZone: "UTC",
  }).format(new Date(isoValue));
}
