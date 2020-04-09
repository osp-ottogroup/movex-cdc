<template>
  <table class="table is-striped is-hoverable">
    <thead>
    <tr>
      <th>Name</th>
      <th>Topic</th>
    </tr>
    </thead>
    <tbody>
    <tr v-for="schema in schemas"
        :key="schema.id"
        @click="setCurrentSchema(schema)"
        :class="{ 'is-selected': isCurrentSchema(schema) }">
      <td>{{ schema.name }}</td>
      <td>
        <b-field>
          <b-input placeholder="Enter Topic"
                   v-model="schema.topic"
                   size="is-small"
                   :icon-right="schema.topicChanged ? 'save' : ''"
                   :icon-right-clickable="schema.topicChanged"
                   @icon-right-click="onSaveSchema(schema)"
                   @input="onTopicChanged(schema)">
          </b-input>
        </b-field>
      </td>
    </tr>
    </tbody>
  </table>
</template>

<script>
import CRUDService from '../../services/CRUDService';

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
    async onSaveSchema(schema) {
      try {
        await CRUDService.schemas.update(schema.id, { schema });
        // eslint-disable-next-line no-param-reassign
        schema.topicChanged = false;
        this.$buefy.toast.open({
          message: `Saved changes to schema '${schema.name}'!`,
          type: 'is-success',
        });
      } catch (e) {
        this.$buefy.toast.open({
          message: 'An error occurred!',
          type: 'is-danger',
          duration: 5000,
        });
      }
    },
    onTopicChanged(schema) {
      if (!schema.topicChanged) {
        this.$set(schema, 'topicChanged', true);
      }
    },
  },
};
</script>
