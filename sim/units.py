"""Unit conversions and physical constants.

The sim works in SI units internally. Convert to mph, hp, lb-ft, etc. only
at the edges (data entry and display), never inside physics code.
"""
import math

# Physical constants
G = 9.81            # m/s^2
RHO_AIR = 1.225     # kg/m^3, sea level
AMBIENT_C = 30.0    # C, default air temperature (and cold brake temperature)

# Conversions
LBFT_TO_NM = 1.3558179
HP_TO_W = 745.69987
MPH_TO_MS = 0.44704
KMH_TO_MS = 1 / 3.6
FT_TO_M = 0.3048
RPM_TO_RADS = 2 * math.pi / 60
