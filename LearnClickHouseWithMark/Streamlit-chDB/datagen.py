import pandas as pd
import numpy as np
from datetime import datetime, timedelta

# Function to generate ISO 8601 date string and epoch timestamp
def generate_datetime_info(dt):
    iso_format = dt.isoformat() + 'Z'
    epoch_timestamp = int(dt.timestamp())
    return iso_format, epoch_timestamp

# Function to determine usage stats based on month and energy type
def get_usage_stats(month, energy_type):
    # Rough average values based on the provided table
    avg_stats = {
        'electricity': {
            'winter': {'min': 0.05, 'avg': 0.25, 'max': 1.8},
            'spring': {'min': 0.045, 'avg': 0.16, 'max': 2.0},
            'summer': {'min': 0.027, 'avg': 0.15, 'max': 1.5},
            'autumn': {'min': 0.05, 'avg': 0.16, 'max': 1.6}
        },
        'gas': {
            'winter': {'min': 0, 'avg': 1.2, 'max': 16},
            'spring': {'min': 0, 'avg': 0.45, 'max': 12},
            'summer': {'min': 0, 'avg': 0.15, 'max': 10},
            'autumn': {'min': 0, 'avg': 0.21, 'max': 11}
        }
    }

    # Determine the season
    if month in [12, 1, 2]:
        season = 'winter'
    elif month in [3, 4, 5]:
        season = 'spring'
    elif month in [6, 7, 8]:
        season = 'summer'
    else:
        season = 'autumn'

    return avg_stats[energy_type][season]

# Function to simulate energy usage
def simulate_energy_usage(start_date, end_date):
    datetime_range = pd.date_range(start=start_date, end=end_date, freq='30min')
    data = []

    evening_hours = range(17, 22)
    early_morning_hours = range(5, 9)  # From 5:00 AM to 8:30 AM

    for dt in datetime_range:
        month = dt.month
        iso_format, epoch_timestamp = generate_datetime_info(dt)

        # Simulate electricity usage
        elec_stats = get_usage_stats(month, 'electricity')
        electricity_usage = np.random.uniform(elec_stats['min'], elec_stats['max'])
        electricity_usage = max(min(electricity_usage, elec_stats['max']), elec_stats['min'])
        data.append(['electricity', epoch_timestamp, round(electricity_usage, 3), iso_format])

        # Simulate gas usage
        gas_stats = get_usage_stats(month, 'gas')
        if dt.hour in evening_hours or dt.hour in early_morning_hours:
            gas_usage = np.random.uniform(gas_stats['min'], gas_stats['max'])
            gas_usage = max(min(gas_usage, gas_stats['max']), gas_stats['min'])
            data.append(['gas', epoch_timestamp, round(gas_usage, 3), iso_format])
        else:
            data.append(['gas', epoch_timestamp, 0, iso_format])

    return pd.DataFrame(data, columns=['energyType', 'epochTimestamp', 'kWh', 'dateTime'])

# Example usage of the function
start_date = '2023-01-01'
end_date = '2024-01-02'
simulated_data = simulate_energy_usage(start_date, end_date)

# Print the first few rows of the simulated data
print(simulated_data.head(n=50))

simulated_data.to_csv("data.csv", index=False)
