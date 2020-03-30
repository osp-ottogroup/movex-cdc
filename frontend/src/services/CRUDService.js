// @ts-check

import BaseCRUDService from './BaseCRUDService';

export default {
  columns: BaseCRUDService('columns'),
  schemaRights: BaseCRUDService('schema_rights'),
  schemas: BaseCRUDService('schemas'),
  tables: BaseCRUDService('tables'),
  users: BaseCRUDService('users'),
  dbColumns: { getAll: BaseCRUDService('db_columns').getAll },
  dbSchemas: { getAll: BaseCRUDService('db_schemas').getAll },
  dbTables: { getAll: BaseCRUDService('db_tables').getAll },
};
