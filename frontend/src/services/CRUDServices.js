// @ts-check

import BaseCRUDService from './BaseCRUDService';
import HttpService from './HttpService';
import Config from '../config/config';

const schemaRights = {
  ...BaseCRUDService('schema_rights'),
  async getForUser(userId) {
    return (await HttpService.get(`${Config.backendUrl}/schema_rights`, { user_id: userId })).data;
  },
};

export default {
  schemaRights,
  schemas: BaseCRUDService('schemas'),
  tables: BaseCRUDService('tables'),
  users: BaseCRUDService('users'),
  dbSchemas: { getAll: BaseCRUDService('db_schemas').getAll },
  dbTables: { getAll: BaseCRUDService('db_tables').getAll },
  dbColumns: { getAll: BaseCRUDService('db_columns').getAll },
};
