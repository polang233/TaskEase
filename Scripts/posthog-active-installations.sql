-- 包含今天的最近 30 个 UTC 日期，按匿名安装标识去重。
SELECT uniqExact(distinct_id) AS users FROM events WHERE event = 'taskease daily active' AND properties.is_test = false AND timestamp >= toStartOfDay(now() - INTERVAL 29 DAY);
