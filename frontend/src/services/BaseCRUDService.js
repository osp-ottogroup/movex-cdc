import HttpService from './HttpService';
import Config from '../config/config';

const { backendUrl } = Config;

export default (name) => ({
  getAll: async (urlParams) => (await HttpService.get(`${backendUrl}/${name}`, urlParams)).data,
  get: async (id) => (await HttpService.get(`${backendUrl}/${name}/${id}`)).data,
  delete: async (id, object) => (await HttpService.delete(`${backendUrl}/${name}/${id}`, object)).data,
  update: async (id, object) => (await HttpService.put(`${backendUrl}/${name}/${id}`, object)).data,
  create: async (object) => (await HttpService.post(`${backendUrl}/${name}`, object)).data,

  // Synchronous-like variants (resolve promise immediately), used to avoid async/await in some contexts
  getAll_sync: (urlParams) => HttpService.get(`${backendUrl}/${name}`, urlParams).then((res) => res.data),
  get_sync: (id) => HttpService.get(`${backendUrl}/${name}/${id}`).then((res) => res.data),
  delete_sync: (id, object) => HttpService.delete(`${backendUrl}/${name}/${id}`, object).then((res) => res.data),
  update_sync: (id, object) => HttpService.put(`${backendUrl}/${name}/${id}`, object).then((res) => res.data),
  create_sync: (object) => HttpService.post(`${backendUrl}/${name}`, object).then((res) => res.data),
});
