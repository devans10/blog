#!/usr/bin/python env

import pandas as pd
import matplotlib.pyplot as plt

plt.style.use("fivethirtyeight")

data = pd.read_csv("../src/data/runs.csv")

data = data.set_index(pd.DatetimeIndex(data["date"].values))


weeklyAvgDistance = data["distance"].mean()

plt.figure(figsize=(12.2, 12.5))
# data.plot.bar(y="distance")
# plt.plot(weeklyAvgDistance)
plt.autoscale(enable=False)
plt.figure()
plt.bar(data.index, data["distance"])
plt.xticks(rotation=45)
plt.title("Distance")
plt.xlabel("Date")
plt.ylabel("Miles")


plt.savefig("../src/static/img/run_distance.png", format="png", bbox_inches="tight")

# plt.show()
