import type { ExtractParsedContentFromParams, ParsedMessage } from "@anthropic-ai/sdk/lib/parser";
import type { MessageCreateParamsNonStreaming, StopReason } from "@anthropic-ai/sdk/resources/messages";
import type { AnthropicLike } from "../../src/model.js";

export interface CannedResponse {
  text: string;
  stopReason?: StopReason;
  refusalCategory?: string | null;
  leadingThinking?: boolean;
}

/** Records every request and answers from a queue, running the request's own output parser like the SDK does. */
export class FakeAnthropic implements AnthropicLike {
  readonly calls: MessageCreateParamsNonStreaming[] = [];
  private readonly queue: Array<CannedResponse | Error> = [];

  reply(response: CannedResponse | Error): this {
    this.queue.push(response);
    return this;
  }

  replyJson(value: unknown): this {
    return this.reply({ text: JSON.stringify(value) });
  }

  readonly messages = {
    parse: async <Params extends MessageCreateParamsNonStreaming>(
      params: Params,
    ): Promise<ParsedMessage<ExtractParsedContentFromParams<Params>>> => {
      this.calls.push(params);
      const next = this.queue.shift();
      if (!next) throw new Error("FakeAnthropic: no canned response queued");
      if (next instanceof Error) throw next;
      const format = params.output_config?.format;
      const parsed = format && "parse" in format ? (format as { parse(text: string): unknown }).parse(next.text) : null;
      const textBlock = { type: "text", text: next.text, citations: null };
      const content = next.leadingThinking ? [{ type: "thinking", thinking: "", signature: "sig" }, textBlock] : [textBlock];
      return {
        id: "msg_test",
        type: "message",
        role: "assistant",
        model: params.model,
        content,
        stop_reason: next.stopReason ?? "end_turn",
        stop_sequence: null,
        stop_details:
          next.stopReason === "refusal"
            ? { type: "refusal", category: next.refusalCategory ?? null, explanation: null }
            : null,
        usage: {
          input_tokens: 1200,
          output_tokens: 300,
          cache_read_input_tokens: 900,
          cache_creation_input_tokens: 0,
        },
        parsed_output: parsed,
      } as unknown as ParsedMessage<ExtractParsedContentFromParams<Params>>;
    },
  };
}
