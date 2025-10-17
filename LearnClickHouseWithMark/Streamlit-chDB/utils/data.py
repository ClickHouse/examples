import pandas as pd

class EnergyUsage:    
    def __init__(self, usage_df):
        self.usage_df = usage_df

    def usage(self):
        return float(self.usage_df['totalUsage'].values[0])

    def standing_charge(self):
        return round(self.usage_df['standingCharge'].values[0]/100, 2)

    def unit_rate(self):
        return round(self.usage_df['unitRate'].values[0]/100, 2)

    def cost(self):
        return round(float(self.usage_df['cost'].values[0]), 2)

    def table(self, selected_date, friendly_comparison, alternate):
        return pd.DataFrame({
            "Concept": ["Standing charge", "Unit rate", "Total cost"],
            f"Cost on {selected_date.strftime('%d %b %Y')}": [
                f"£{self.standing_charge():.2f}",
                f"£{self.unit_rate():.2f}",
                f"£{self.cost():.2f}"
                ],
            f"Cost from {friendly_comparison}": [
                f"£{alternate.standing_charge:.2f}", 
                f"£{alternate.unit_rate:.2f}",  
                f"£{alternate.cost(self.usage()):.2f}"
            ],
            "Difference": [
                alternate.standing_charge - self.standing_charge()  ,
                alternate.unit_rate - self.unit_rate(),
                alternate.cost(self.usage()) - self.cost()
            ]
        })    

class AlternateUsage:
    def __init__(self, standing_charge, unit_rate):
        self.standing_charge = standing_charge
        self.unit_rate = unit_rate

    def cost(self, usage):
        return self.standing_charge + (usage * self.unit_rate)
