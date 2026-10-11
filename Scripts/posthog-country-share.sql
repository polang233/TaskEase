-- 每个安装只归入最后上报的系统地区，保证国家占比使用相同去重口径。
SELECT CASE
    WHEN region = 'CN' THEN '中国'
    WHEN region = 'TW' THEN '台湾'
    WHEN region = 'HK' THEN '香港'
    WHEN region = 'MO' THEN '澳门'
    WHEN region = 'US' THEN '美国'
    WHEN region = 'JP' THEN '日本'
    WHEN region = 'KR' THEN '韩国'
    WHEN region = 'SG' THEN '新加坡'
    WHEN region = 'GB' THEN '英国'
    WHEN region = 'DE' THEN '德国'
    WHEN region = 'FR' THEN '法国'
    WHEN region = 'CA' THEN '加拿大'
    WHEN region = 'AU' THEN '澳大利亚'
    WHEN region = 'IN' THEN '印度'
    WHEN region = 'RU' THEN '俄罗斯'
    WHEN region = 'unknown' THEN '未知'
    WHEN region = '' THEN '未知'
    ELSE region
END AS country, count() AS users
FROM (
    SELECT distinct_id, argMax(coalesce(toString(properties.region), 'unknown'), timestamp) AS region FROM events WHERE event = 'taskease daily active' AND properties.is_test = false AND timestamp >= toStartOfDay(now() - INTERVAL 29 DAY)
    GROUP BY distinct_id
)
GROUP BY country
ORDER BY users DESC;
