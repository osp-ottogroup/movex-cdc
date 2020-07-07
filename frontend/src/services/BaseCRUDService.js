import HttpService from './HttpService';
import Config from '../config/config';

const { backendUrl } = Config;

export default name => ({
  getAll: async urlParams => (await HttpService.get(`${backendUrl}/${name}`, urlParams)).data,
  get: async id => (await HttpService.get(`${backendUrl}/${name}/${id}`)).data,
  delete: async (id, object) => (await HttpService.delete(`${backendUrl}/${name}/${id}`, object)).data,
  update: async (id, object) => (await HttpService.put(`${backendUrl}/${name}/${id}`, object)).data,
  create: async object => (await HttpService.post(`${backendUrl}/${name}`, object)).data,
});
