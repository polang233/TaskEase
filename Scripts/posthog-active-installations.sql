-- 过去 30 天的活跃安装与环境分布；核验事件不计入正式统计。
SELECT '30天活跃安装' AS metric, '全部' AS dimension, uniqExact(distinct_id) AS installations
FROM events
WHERE event = 'taskease daily active' AND properties.is_test = false AND timestamp >= now() - INTERVAL 30 DAY
UNION ALL
SELECT '应用版本', toString(properties.app_version), uniqExact(distinct_id)
FROM events
WHERE event = 'taskease daily active' AND properties.is_test = false AND timestamp >= now() - INTERVAL 30 DAY
GROUP BY properties.app_version
UNION ALL
SELECT 'macOS版本', toString(properties.os_version), uniqExact(distinct_id)
FROM events
WHERE event = 'taskease daily active' AND properties.is_test = false AND timestamp >= now() - INTERVAL 30 DAY
GROUP BY properties.os_version
UNION ALL
SELECT '系统地区', toString(properties.region), uniqExact(distinct_id)
FROM events
WHERE event = 'taskease daily active' AND properties.is_test = false AND timestamp >= now() - INTERVAL 30 DAY
GROUP BY properties.region
