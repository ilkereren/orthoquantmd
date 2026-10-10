const crypto = require("node:crypto");
const admin = require("firebase-admin");
const { onRequest } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
const nodemailer = require("nodemailer");

admin.initializeApp();

const openAiApiKey = defineSecret("OPENAI_API_KEY");
const gmailAppPassword = defineSecret("GMAIL_APP_PASSWORD");

const REGION = "europe-west1";
const MODEL = "gpt-5.4-mini";
const WEEKLY_LIMIT = 10;
const MAX_RESULTS = 60;
const SURVEY_EMAIL = "ilker.eren@gmail.com";
const SURVEY_DAILY_LIMIT = 3;
const SURVEY_TEXT_LIMIT = 1000;
const SURVEY_FREQUENCIES = [
  "Daily",
  "Several times a week",
  "Weekly",
  "A few times a month",
  "Rarely",
];

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

exports.submitSurvey = onRequest(
  {
    region: REGION,
    cors: true,
    secrets: [gmailAppPassword],
    timeoutSeconds: 30,
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
      if (!installationId) {
        res.status(400).json({ error: "Missing installation id." });
        return;
      }
      const survey = normalizeSurvey(body);
      if (!survey) {
        res.status(400).json({ error: "Please answer questions 1-3." });
        return;
      }

      await reserveDailySurvey(installationId);

      const installationHash = crypto
        .createHash("sha256")
        .update(installationId)
        .digest("hex")
        .slice(0, 16);
      const ref = await admin
        .firestore()
        .collection("surveyResponses")
        .add({
          ...survey,
          installationHash,
          emailSent: false,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });

      try {
        await sendSurveyEmail(survey, installationHash);
        await ref.update({ emailSent: true });
      } catch (error) {
        // The response is already stored in Firestore; don't fail the user.
        console.error("Survey email failed", ref.id, error);
      }

      res.status(200).json({ ok: true });
    } catch (error) {
      console.error(error);
      const status = error.statusCode || 500;
      res.status(status).json({
        error: error.publicMessage || "Could not submit the survey.",
      });
    }
  },
);

function normalizeSurvey(body) {
  const satisfaction = Number(body.satisfaction);
  const aiHelpfulness = Number(body.aiHelpfulness);
  const frequency = cleanString(body.frequency, 40);
  if (!Number.isInteger(satisfaction) || satisfaction < 1 || satisfaction > 5) {
    return null;
  }
  if (!Number.isInteger(aiHelpfulness) || aiHelpfulness < 0 || aiHelpfulness > 5) {
    return null;
  }
  if (!SURVEY_FREQUENCIES.includes(frequency)) return null;

  const contactEmail = cleanString(body.contactEmail, 254);
  return {
    satisfaction,
    frequency,
    aiHelpfulness,
    featureSuggestion: cleanString(body.featureSuggestion, SURVEY_TEXT_LIMIT),
    templateSuggestion: cleanString(body.templateSuggestion, SURVEY_TEXT_LIMIT),
    otherComments: cleanString(body.otherComments, SURVEY_TEXT_LIMIT),
    contactEmail: /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(contactEmail)
      ? contactEmail
      : "",
    appVersion: cleanLine(body.appVersion, 40),
    platform: cleanLine(body.platform, 80),
    locale: cleanLine(body.locale, 20),
  };
}

function cleanLine(value, maxLength) {
  return cleanString(value, maxLength).replace(/[\r\n]+/g, " ");
}

async function reserveDailySurvey(installationId) {
  const dayId = new Date().toISOString().slice(0, 10);
  const safeId = crypto
    .createHash("sha256")
    .update(`survey:${installationId}:${dayId}`)
    .digest("hex");
  const ref = admin.firestore().collection("surveyRateLimits").doc(safeId);

  await admin.firestore().runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    const count = snapshot.exists ? snapshot.get("count") || 0 : 0;
    if (count >= SURVEY_DAILY_LIMIT) {
      const error = new Error("Daily survey limit reached.");
      error.statusCode = 429;
      error.publicMessage =
        "You have already sent feedback today. Thank you!";
      throw error;
    }
    transaction.set(ref, {
      count: count + 1,
      dayId,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  });
}

async function sendSurveyEmail(survey, installationHash) {
  const transporter = nodemailer.createTransport({
    service: "gmail",
    auth: { user: SURVEY_EMAIL, pass: gmailAppPassword.value() },
  });
  const ai =
    survey.aiHelpfulness === 0 ? "AI n/a" : `AI ${survey.aiHelpfulness}/5`;
  const section = (title, text) => `${title}:\n${text || "-"}\n`;

  await transporter.sendMail({
    from: `"OrthoQuant Survey" <${SURVEY_EMAIL}>`,
    to: SURVEY_EMAIL,
    replyTo: survey.contactEmail || undefined,
    subject:
      `[OrthoQuant Survey] ★${survey.satisfaction}/5 · ${ai} · ` +
      `${survey.platform.split(" ")[0]} ${survey.appVersion}`,
    text: [
      "OrthoQuant MD – User Survey",
      "---------------------------",
      `Satisfaction: ${survey.satisfaction}/5`,
      `Usage frequency: ${survey.frequency}`,
      `AI helpfulness: ${
        survey.aiHelpfulness === 0 ? "Haven't used" : `${survey.aiHelpfulness}/5`
      }`,
      "",
      section("Feature suggestion", survey.featureSuggestion),
      section("Template suggestion", survey.templateSuggestion),
      section("Other comments", survey.otherComments),
      `Contact email: ${survey.contactEmail || "-"}`,
      "---------------------------",
      `App ${survey.appVersion} · ${survey.platform} · ${survey.locale}`,
      `Installation: ${installationHash}`,
    ].join("\n"),
  });
}
