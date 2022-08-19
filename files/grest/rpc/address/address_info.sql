CREATE FUNCTION grest.address_info (_addresses text[])
  RETURNS TABLE (
    address text,
    info json
  )
  LANGUAGE PLPGSQL
  AS $$
BEGIN
  RETURN QUERY
    WITH _all_utxos AS (
      SELECT
        tx.id,
        tx.hash,
        tx_out.address,
        tx_out.value,
        tx_out.index,
        tx_out.stake_address_id,
        tx.block_id,
        tx_out.data_hash,
        tx_out.inline_datum_id,
        tx_out.reference_script_id,
        tx_out.address_has_script
      FROM
        tx_out
        INNER JOIN tx ON tx.id = tx_out.tx_id
        LEFT JOIN tx_in ON tx_in.tx_out_id = tx_out.tx_id
          AND tx_in.tx_out_index = tx_out.index
      WHERE
        tx_in.id IS NULL
        AND 
        tx_out.address = ANY(_addresses)
    )

      SELECT
        ad.address,
        JSON_BUILD_OBJECT(
          'balance', COALESCE(SUM(au.value), '0')::text,
          'stake_address', SA.view,
          'script_address', bool_or(au.address_has_script),
          'utxo_set', 
          CASE WHEN EXISTS (
            SELECT TRUE FROM _all_utxos aus WHERE aus.address=ad.address
          ) THEN
            JSON_AGG(
              JSON_BUILD_OBJECT(
                'tx_hash', ENCODE(au.hash, 'hex'), 
                'tx_index', au.index,
                'block_height', block.block_no,
                'block_time', EXTRACT(epoch from block.time)::integer,
                'value', au.value::text,
                'datum_hash', ENCODE(au.data_hash, 'hex'),
                'inline_datum', ( CASE WHEN au.inline_datum_id IS NULL THEN NULL
                  ELSE
                    JSONB_BUILD_OBJECT(
                      'bytes', ENCODE(datum.bytes, 'hex'),
                      'value', datum.value
                    )
                  END
                ),
                'reference_script', ( CASE WHEN au.reference_script_id IS NULL THEN NULL
                  ELSE
                    JSONB_BUILD_OBJECT(
                      'hash', ENCODE(script.hash, 'hex'),
                      'bytes', ENCODE(script.bytes, 'hex'),
                      'value', script.json,
                      'type', script.type::text,
                      'size', script.serialised_size
                    )
                  END
                ),
                'asset_list', COALESCE(
                  (
                    SELECT
                      JSON_AGG(JSON_BUILD_OBJECT(
                        'policy_id', ENCODE(MA.policy, 'hex'),
                        'asset_name', ENCODE(MA.name, 'hex'),
                        'quantity', MTX.quantity::text
                        ))
                    FROM
                        ma_tx_out MTX
                        INNER JOIN multi_asset MA ON MA.id = MTX.ident
                    WHERE
                        MTX.tx_out_id = au.id
                  ),
                  JSON_BUILD_ARRAY()
                )
              )
            )
          ELSE
            '[]'::json
          END
        )
      FROM
        (SELECT UNNEST(_addresses) as address) ad
        LEFT OUTER JOIN _all_utxos au ON ad.address = au.address
        LEFT JOIN public.block ON block.id = au.block_id
        LEFT JOIN stake_address SA on au.stake_address_id = SA.id
        LEFT JOIN datum ON datum.id = au.inline_datum_id
        LEFT JOIN script ON script.id = au.reference_script_id
      GROUP BY
        ad.address, SA.view;
END;
$$;

COMMENT ON FUNCTION grest.address_info IS 'Get address info - balance, associated stake address (if any) and UTXO set';

