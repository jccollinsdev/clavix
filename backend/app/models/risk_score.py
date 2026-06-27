from pydantic import BaseModel
from typing import Optional, List
from datetime import datetime


class RiskScoreBase(BaseModel):
    financial_health: Optional[float] = None
    news_sentiment: Optional[float] = None
    macro_exposure: Optional[float] = None
    sector_exposure: Optional[float] = None
    volatility: Optional[float] = None
    total_score: Optional[float] = None
    grade: Optional[str] = None
    grade_direction: Optional[str] = None
    score_delta: Optional[int] = None

    # WS-G: risk-score `confidence` removed (was a meaningless constant). Per-article
    # and portfolio confidence live on different models and are unaffected.
    safety_score: Optional[float] = None

    reasoning: Optional[str] = None
    evidence_summary: Optional[str] = None
    dimension_rationale: Optional[dict] = None
    factor_breakdown: Optional[dict] = None


class RiskScoreCreate(RiskScoreBase):
    position_id: str
    analysis_run_id: Optional[str] = None


class RiskScore(RiskScoreBase):
    id: str
    position_id: str
    analysis_run_id: Optional[str] = None
    calculated_at: datetime

    class Config:
        from_attributes = True
