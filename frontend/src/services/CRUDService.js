// @ts-check

import Config from '@/config/config';
import BaseCRUDService from './BaseCRUDService';
import HttpService from './HttpService';

const { backendUrl } = Config;

export default {
  activityLog: {
    get: BaseCRUDService('activity_logs').getAll,
  },
  columns: {
    ...BaseCRUDService('columns'),
    selectAll: async (object) => (await HttpService.post(`${backendUrl}/columns/select_all_columns`, object)).data,
    deselectAll: async (object) => (await HttpService.post(`${backendUrl}/columns/deselect_all_columns`, object)).data,
  },
  conditions: BaseCRUDService('conditions'),
  schemaRights: BaseCRUDService('schema_rights'),
  schemas: BaseCRUDService('schemas'),
  tables: {
    ...BaseCRUDService('tables'),
    triggerDates: BaseCRUDService('/trigger_dates').get,
  },
  users: {
    ...BaseCRUDService('users'),
    deployableSchemas: async (user) => (await HttpService.get(`${backendUrl}/users/${user.id}/deployable_schemas`)).data,
  },
  dbColumns: { getAll: BaseCRUDService('db_columns').getAll },
  dbSchemas: {
    getAll: BaseCRUDService('db_schemas').getAll,
    // gets all db schemas, which can be authorized to the user
    // (schemas, which have tables and are currently not authorized to the user)
    authorizableSchemas: BaseCRUDService('db_schemas/authorizable_schemas').getAll,
  },
  dbTables: { getAll: BaseCRUDService('db_tables').getAll },
  healthCheck: {
    check: BaseCRUDService('/health_check').getAll,
    getLogFile: BaseCRUDService('/health_check/log_file').getAll,
  },
  serverControl: {
    getLogLevel: async (object) => (await HttpService.get(`${backendUrl}/server_control/get_log_level`, object)).data,
    setLogLevel: async (object) => (await HttpService.post(`${backendUrl}/server_control/set_log_level`, object)).data,
  },
  kafka: {
    topics: {
      getAll: BaseCRUDService('kafka/topics').getAll,
      get: async (object) => (await HttpService.get(`${backendUrl}/kafka/describe_topic`, object)).data,
    },
    groups: {
      getAll: BaseCRUDService('kafka/groups').getAll,
      get: async (object) => (await HttpService.get(`${backendUrl}/kafka/describe_group`, object)).data,
    },
  },
  instance: {
    info: async () => (await HttpService.get(`${Config.backendUrl}/health_check/config_info`)).data,
  },
};
