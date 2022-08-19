CREATE FUNCTION grest.address_assets (_addresses text[])
  RETURNS TABLE (
    address varchar,
    assets json
  )
  LANGUAGE PLPGSQL
  AS $$
BEGIN
  RETURN QUERY

  WITH _all_assets AS (
    SELECT
      txo.address,
      ma.policy,
      ma.name,
      SUM(mtx.quantity) as quantity
    FROM
      MA_TX_OUT MTX
      INNER JOIN MULTI_ASSET MA ON MA.id = MTX.ident
      INNER JOIN TX_OUT TXO on TXO.ID = MTX.TX_OUT_ID
      LEFT JOIN TX_IN on TXO.TX_ID = TX_IN.TX_OUT_ID
        AND TXO.INDEX::smallint = TX_IN.TX_OUT_INDEX::smallint
    WHERE
      TXO.address = ANY(_addresses)
      AND TX_IN.TX_IN_ID IS NULL
    GROUP BY
      TXO.address, MA.policy, MA.name
  )

  SELECT
    aa.address,
    JSON_BUILD_OBJECT(
      'policy_id', ENCODE(aa.policy, 'hex'),
      'assets', JSON_AGG( JSON_BUILD_OBJECT(
        'asset_name', ENCODE(aa.name, 'hex'),
        'balance', aa.quantity::text)
      )
    )
  FROM
    _all_assets aa
  GROUP BY
    aa.address, aa.policy;
END;
$$;

COMMENT ON FUNCTION grest.address_assets IS 'Get the list of all the assets (policy, name and quantity) for given addresses';

