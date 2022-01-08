#!/usr/bin/python env

import pandas as pd
import matplotlib.pyplot as plt


def get_sec(time_str):
    """Get Seconds from time."""
    h, m, s = time_str.split(":")
    return int(h) * 3600 + int(m) * 60 + int(s)


plt.style.use("fivethirtyeight")

data = pd.read_csv("../src/data/runs.csv")

data = data.set_index(pd.DatetimeIndex(data["date"].values))

pace = []
for time in data["time"]:
    secs = get_sec(time)
    pace.append(secs)

data["time_secs"] = pace

data["pace"] = data["time_secs"] / data["distance"]

plt.figure(figsize=(12.2, 12.5))

plt.autoscale(enable=False)
plt.figure()
plt.bar(data.index, (data["pace"] / 60))
plt.xticks(rotation=45)
plt.title("Pace")
plt.xlabel("Date")
plt.ylabel("Minutes per Mile")


plt.savefig("../src/images/run_time.png", format="png", bbox_inches="tight")

# plt.show()
