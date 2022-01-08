#!/usr/bin/python env

import pandas as pd
import matplotlib.pyplot as plt

plt.style.use("fivethirtyeight")

data = pd.read_csv("src/data/runs.csv")

data = data.set_index(pd.DatetimeIndex(data["date"].values))


weeklyAvgDistance = data["cadence"].mean()

plt.figure(figsize=(12.2, 12.5))
# data.plot.bar(y="distance")
# plt.plot(weeklyAvgDistance)
plt.autoscale(enable=False)
plt.figure()
plt.bar(data.index, data["cadence"])
plt.xticks(rotation=45)
plt.title("Cadence")
plt.xlabel("Date")
plt.ylabel("Steps per Minute")


plt.savefig("../src/static/img/run_cadence.png", format="png", bbox_inches="tight")

# plt.show()
