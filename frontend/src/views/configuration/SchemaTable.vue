<template>
  <table class="table is-striped is-hoverable">
    <thead>
    <tr>
      <th>
        Schemas
      </th>
    </tr>
    </thead>
    <tbody>
    <tr v-for="schema in schemas"
        :key="schema.id"
        @click="setCurrentSchema(schema)"
        :class="{ 'is-selected': isCurrentSchema(schema) }">
      <td>{{ schema.name }}</td>
    </tr>
    </tbody>
  </table>
</template>

<script>
export default {
  name: 'SchemaTable',
  props: {
    schemas: { type: Array, default: () => [] },
  },
  data() {
    return {
      currentSchema: null,
    };
  },
  methods: {
    setCurrentSchema(schema) {
      this.currentSchema = schema;
      this.$emit('schema-selected', schema);
    },
    isCurrentSchema(schema) {
      return this.currentSchema && this.currentSchema.id === schema.id;
    },
  },
};
</script>
