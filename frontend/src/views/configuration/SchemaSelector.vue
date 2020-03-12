<template>
  <div>
    <schema-table :schemas="schemas"
                  v-on="$listeners"/>
  </div>
</template>

<script>
import SchemaTable from './SchemaTable.vue';

export default {
  name: 'SchemaSelector',
  components: {
    SchemaTable,
  },
  props: {
    schemas: { type: Array, default: () => [] },
  },
};
</script>
