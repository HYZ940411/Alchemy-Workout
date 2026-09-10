"""
經驗值服務 - 負責經驗值計算和升級邏輯
"""


class ExperienceService:
    """經驗值服務（符合 SRP - 單一職責原則）"""
    
    @staticmethod
    def calculate_level(exp: int) -> int:
        """根據經驗值計算等級（每 150 exp 升一級）"""
        return 1 + (exp // 150)
    
    @staticmethod
    def calculate_level_up(old_exp: int, new_exp: int) -> dict:
        """計算經驗值獎勵和升級資訊"""
        old_level = ExperienceService.calculate_level(old_exp)
        new_level = ExperienceService.calculate_level(new_exp)
        
        return {
            "exp": new_exp,
            "oldLevel": old_level,
            "newLevel": new_level,
            "levelUp": new_level > old_level
        }

