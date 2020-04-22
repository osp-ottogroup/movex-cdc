<template>
  <div class="content">
    <schema-table :schemas="schemas"
                  v-on="$listeners"/>
  </div>
</template>

<script>
import SchemaTable from './SchemaTable.vue';
import CRUDService from '../../services/CRUDService';
import { getErrorMessageAsHtml } from '@/helpers';

export default {
  name: 'SchemaSelector',
  components: {
    SchemaTable,
  },
  data() {
    return {
      schemas: [],
    };
  },
  async mounted() {
    try {
      this.schemas = await CRUDService.schemas.getAll();
    } catch (e) {
      this.$buefy.toast.open({
        message: getErrorMessageAsHtml(e, 'An error occurred while loading schemas!'),
        type: 'is-danger',
        duration: 5000,
      });
    }
  },
};
</script>
