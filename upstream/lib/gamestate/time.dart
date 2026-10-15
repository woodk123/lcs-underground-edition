/// Advances the simulation's calendar once, independent of daylight saving.
DateTime nextCampaignDay(DateTime current) => current.isUtc
    ? DateTime.utc(current.year, current.month, current.day + 1)
    : DateTime(current.year, current.month, current.day + 1);

String getMonth(int month) => [
  "January",
  "February",
  "March",
  "April",
  "May",
  "June",
  "July",
  "August",
  "September",
  "October",
  "November",
  "December",
][month - 1];

String getMonthShort(int month) => [
  "Jan",
  "Feb",
  "Mar",
  "Apr",
  "May",
  "Jun",
  "Jul",
  "Aug",
  "Sep",
  "Oct",
  "Nov",
  "Dec",
][month - 1];
