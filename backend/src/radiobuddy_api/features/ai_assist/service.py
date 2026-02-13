from __future__ import annotations

import json

import httpx

from radiobuddy_api.features.ai_assist.schemas import AiAssistAnalyzeIn, AiAssistAnalyzeOut
from radiobuddy_api.platform.config import settings


def _local_instruction(payload: AiAssistAnalyzeIn) -> str:
    metrics = payload.metrics
    pose_conf = metrics.get("pose_confidence", 0.0)
    framing = metrics.get("framing_score", 0.0)
    motion = metrics.get("motion_score", 0.0)
    rotation = metrics.get("rotation_risk", 0.0)
    tilt = metrics.get("tilt_risk", 0.0)
    chin = metrics.get("chin_risk", 0.0)
    scap = metrics.get("scapula_risk", 0.0)

    if pose_conf < 0.55:
        return "Step back and keep full torso in view."
    if framing < 0.6:
        return "Center the patient in frame."
    if motion > 0.55:
        return "Hold still briefly before exposure."
    if rotation > 0.6:
        return "Reduce patient rotation slightly."
    if tilt > 0.6:
        return "Straighten up to reduce lateral tilt."
    if chin > 0.6:
        return "Lift the chin slightly."
    if scap > 0.6:
        return "Roll shoulders forward slightly."
    return "Positioning looks good. Hold still."


async def _do_inference_instruction(payload: AiAssistAnalyzeIn) -> str:
    key = settings.do_model_access_key
    model = settings.do_model_id
    if not key or not model:
        raise RuntimeError("model_credentials_missing")

    system_prompt = (
        "You are an xray positioning assistant for chest PA erect. "
        "Return one concise instruction under 14 words. "
        "Do not include warnings, disclaimers, or extra explanation."
    )
    user_payload = {
        "procedure_id": payload.procedure_id,
        "stage_id": payload.stage_id,
        "metrics": payload.metrics,
    }

    request_body = {
        "model": model,
        "temperature": 0.1,
        "max_tokens": 40,
        "messages": [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": json.dumps(user_payload)},
        ],
    }

    async with httpx.AsyncClient(timeout=settings.do_inference_timeout_seconds) as client:
        response = await client.post(
            "https://inference.do-ai.run/v1/chat/completions",
            headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"},
            json=request_body,
        )
        response.raise_for_status()
        data = response.json()

    choices = data.get("choices", [])
    if not choices:
        raise RuntimeError("empty_choices")
    message = choices[0].get("message", {})
    content = message.get("content", "")
    if not isinstance(content, str) or not content.strip():
        raise RuntimeError("empty_content")
    return content.strip()


async def analyze_position(payload: AiAssistAnalyzeIn) -> AiAssistAnalyzeOut:
    model = settings.do_model_id
    if settings.do_inference_enabled and settings.do_model_access_key:
        try:
            instruction = await _do_inference_instruction(payload)
            return AiAssistAnalyzeOut(instruction=instruction, source="do_inference", model=model)
        except Exception:
            return AiAssistAnalyzeOut(
                instruction=_local_instruction(payload),
                source="do_inference_fallback",
                model=model,
            )

    return AiAssistAnalyzeOut(
        instruction=_local_instruction(payload),
        source="local",
        model=model,
    )
