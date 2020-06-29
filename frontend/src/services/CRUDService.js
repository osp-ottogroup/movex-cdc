// @ts-check

import BaseCRUDService from './BaseCRUDService';

export default {
  columns: BaseCRUDService('columns'),
  schemaRights: BaseCRUDService('schema_rights'),
  schemas: BaseCRUDService('schemas'),
  tables: {
    ...BaseCRUDService('tables'),
    triggerDates: BaseCRUDService('/trigger_dates').get,
  },
  users: BaseCRUDService('users'),
  dbColumns: { getAll: BaseCRUDService('db_columns').getAll },
  dbSchemas: {
    getAll: BaseCRUDService('db_schemas').getAll,
    // gets all db schemas, which can be authorized to the user
    // (schemas, which have tables and are currently not authorized to the user)
    authorizableSchemas: BaseCRUDService('db_schemas/authorizable_schemas').getAll,
  },
  dbTables: { getAll: BaseCRUDService('db_tables').getAll },
};
