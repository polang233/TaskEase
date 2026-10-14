-- 每个安装只归入最后上报的系统地区，保证国家占比使用相同去重口径。
SELECT CASE
    WHEN region = 'CN' THEN 'China'
    WHEN region = 'TW' THEN 'Taiwan'
    WHEN region = 'HK' THEN 'Hong Kong'
    WHEN region = 'MO' THEN 'Macao'
    WHEN region = 'US' THEN 'United States'
    WHEN region = 'JP' THEN 'Japan'
    WHEN region = 'KR' THEN 'South Korea'
    WHEN region = 'SG' THEN 'Singapore'
    WHEN region = 'GB' THEN 'United Kingdom'
    WHEN region = 'DE' THEN 'Germany'
    WHEN region = 'FR' THEN 'France'
    WHEN region = 'CA' THEN 'Canada'
    WHEN region = 'AU' THEN 'Australia'
    WHEN region = 'IN' THEN 'India'
    WHEN region = 'RU' THEN 'Russia'
    WHEN region = 'unknown' THEN 'Unknown'
    WHEN region = '' THEN 'Unknown'
    ELSE region
END AS country, count() AS users
FROM (
    SELECT distinct_id, argMax(coalesce(toString(properties.region), 'unknown'), timestamp) AS region FROM events WHERE event = 'taskease daily active' AND properties.is_test = false AND timestamp >= toStartOfDay(now() - INTERVAL 29 DAY)
    GROUP BY distinct_id
)
GROUP BY country
ORDER BY users DESC;
