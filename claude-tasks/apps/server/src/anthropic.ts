import Anthropic from "@anthropic-ai/sdk";

export const anthropic = new Anthropic({
  apiKey: process.env.ANTHROPIC_API_KEY,
});

export const HAIKU = "claude-haiku-4-5-20251001";
export const OPUS = "claude-opus-4-7";
